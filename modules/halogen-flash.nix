{ pkgs, lib, hostConfig, ... }:
let
  # halogen-flash-server — a Strix Halo (gfx1151) engine built for exactly one
  # model, Qwen3.8-Flash-Next. Upstream:
  #   https://github.com/peonist-ai/halogen-flash-server
  #
  # Recommended deployment (from the upstream quickstart):
  #   weights repo   : peonist-ai/halogen-qwen3.8-flash-next  (public, ~130 GiB)
  #   weights folder : ~/halogen-models                       (mounted at /models)
  #   image          : ghcr.io/peonist-ai/halogen-flash-server:0.5.8
  #
  # This server wants most of a 128 GB machine once it is loaded: the weights
  # stay resident and the KV pool is reserved up front.
  #
  # It is gated by `enableLlm` exactly like every other backend, so all of them
  # spawn together. Which ones you actually keep loaded at the same time is your
  # call, not something this config enforces — watch the pinned weights plus
  # whatever ollama and llama-server load alongside it.
  llmEnabled = hostConfig.enableLlm;

  weightsRepo = "peonist-ai/halogen-qwen3.8-flash-next";
  image = "ghcr.io/peonist-ai/halogen-flash-server:0.5.8";

  # ---- Tuning knobs (all read once at container start) ------------------------
  #
  # WHY THESE ARE PINNED BY HAND. With nothing set, the engine sizes the pool from
  # MemAvailable at the moment it boots and LOWERS ITSELF when the arithmetic
  # does not work out, so which pool you get depends on what happened to be open
  # when the session came up. Our startup log showed exactly that:
  #
  #   kv pool: host RAM 123 GiB, less 67.7 resident weights and 20.0 reserved
  #            for the n-gram page cache and the OS = 35.8 GiB for the device
  #   kv pool: 524288 positions need ~35.0 GiB (plus 1.5 of margin) and host
  #            RAM cannot spare it. LOWERING THE POOL TO 262144 (~27.8 GiB).
  #
  # The 1.5 GiB of margin is the vision tower we ask for (0.84 GiB of pinned
  # weights + ~1.14 GiB of scratch at HALOGEN_VISION_MAX_PIXELS). Since we use
  # images, that charge stays, and 35.8 GiB of device budget cannot carry
  # 36.5. So we choose 262144 deliberately instead of discovering it at boot.
  #
  # WHY 262144 IS ALSO THE FASTER CHOICE FOR THIS BOX. The pool takes RAM that
  # the page cache would otherwise keep for the model's 47.7 GiB n-gram lookup
  # table, which the engine reads through the file cache rather than holding.
  # Fewer pool positions => more cache => cold prompts read from RAM instead of
  # NVMe. Per-stream decode speed is unaffected either way ("generation speed
  # follows a conversation's own length, not the pool"); what 524288 buys is a
  # second *resident* full-length conversation. On a machine that also runs a
  # KDE session, the cache is worth more than the second conversation.
  #
  # To take the second conversation anyway, set kvPoolPositions = "524288" AND
  # hostReserveGiB = "18" (55.8 - 18 = 37.8 GiB of device budget against the
  # ~36.5 needed). If long prompts then crawl with the disk busy and the process
  # in uninterruptible sleep, that trade went the wrong way — come back here.
  kvPoolPositions = "262144";
  hostReserveGiB = "20";
  kvSlots = "4";

  # Keep the weights locked in RAM. The published decode speeds are measured with
  # this ON; `0` hands back a lot of memory and costs several times the decode
  # speed. Only reach for it if another huge workload must share this host.
  pinTrunk = "1";

  # Images. We need them, so the tower loads. The scratch scales with this cap,
  # so it is also the cheapest knob to turn if the pool budget gets tight again:
  # README notes 4K reads no better than 1440p, and 1080p is plenty for text,
  # so lowering it trades detail you were not getting for RAM you can use.
  visionMaxPixels = "3686400"; # 2560x1440 (upstream default)
  # visionMaxPixels = "2073600"; # 1920x1080 -> frees ~0.5 GiB of vision scratch

  # Best-effort image refresh before each start. A failure is not fatal (leading
  # "-") and the cached image still runs. Set to false to take the network out
  # of the start path entirely — with `halogenDownload = false` below, the
  # container then makes no outbound connections at all.
  pullImage = true;

  # The ~130 GiB weights are already on disk in ~/halogen-models, so the volume
  # goes back read-only and the download env goes away. That is the upstream
  # recommendation once the weights are in place: nothing to clobber, nothing to
  # re-verify, no outbound fetch on start. Flip to true only to re-download.
  halogenDownload = false;

  # Kept on one continuation line so turning the download off cannot leave a
  # bare `\` followed by an empty line, which would end the exec early and turn
  # the remaining flags into a command that does not exist.
  downloadEnvArg = lib.optionalString halogenDownload "--env HALOGEN_DOWNLOAD=${weightsRepo} ";

  # The mount mode follows the download switch. The entrypoint refuses to download into
  # a read-only volume, so enabling halogenDownload while leaving `:ro` would just fail
  # the start; deriving one from the other keeps them from drifting apart.
  modelsMountOpt = if halogenDownload then "" else ":ro";
in
{
  # Run the server. Rootless podman, one container ("all" mode): the engine
  # binds loopback inside the container and the OpenAI-compatible front-end is
  # published on :8731 (loopback-only on the host).
  systemd.user.services.halogen-flash-server = lib.mkIf llmEnabled {
    Unit = {
      Description = "halogen-flash server (Qwen3.8-Flash-Next, OpenAI API :8731)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];

      # A crash loop here is not a cheap crash loop: every restart re-pins ~68 GiB
      # of weights and re-reads them through the page cache, and a re-pin that
      # fights a fragmented host can burn tens of minutes at 100% of one core.
      # Three tries per fifteen minutes, then stop and leave it down.
      StartLimitIntervalSec = 900;
      StartLimitBurst = 3;
    };

    Install.WantedBy = [ "default.target" ];
    # WantedBy used to be graphical-session.target, which put this *behind* the
    # desktop in the race for RAM: Plasma, browsers and everything else grab
    # pages and fragment them before the 68 GiB pin starts. With lingering on
    # (users.users.alexfneves.linger = true in /etc/nixos/configuration.nix)
    # default.target starts this at login ahead of the session, so the weights get
    # contiguous memory first. Verified in the startup log by the line
    #   "host memory: N contiguous 2 MiB blocks ... free"
    # — a bigger N means an easier start.

    Service = {
      # systemd gives user units a minimal PATH; the nixpkgs podman needs its
      # helper wrapper (crun/conmon) and the setuid newuidmap/newgidmap helpers
      # in /run/wrappers/bin for rootless operation.
      Environment = [
        "PATH=${pkgs.podman}/bin:/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin"
        "HALOGEN_API_PORT=8731"
        "HALOGEN_KV_POOL_POSITIONS=${kvPoolPositions}"
        "HALOGEN_HOST_RESERVE_GIB=${hostReserveGiB}"
        "HALOGEN_KV_SLOTS=${kvSlots}"
        "HALOGEN_FLASH_PIN_TRUNK=${pinTrunk}"
        "HALOGEN_VISION_TOWER=1"
        "HALOGEN_VISION_MAX_PIXELS=${visionMaxPixels}"
      ];

      # Refresh the image when the network is up; not fatal if it fails.
      ExecStartPre = lib.mkIf pullImage "-${pkgs.podman}/bin/podman pull ${image}";

      ExecStart = pkgs.writeShellScript "halogen-flash-server" ''
        exec ${pkgs.podman}/bin/podman run --rm --replace \
          --name halogen-flash-server \
          --publish 127.0.0.1:8731:8731 \
          --device /dev/kfd \
          --device /dev/dri \
          --group-add keep-groups \
          --security-opt seccomp=unconfined \
          --ipc=host \
          --ulimit memlock=-1:-1 \
          ${downloadEnvArg}--volume "$HOME/halogen-models:/models${modelsMountOpt}" \
          ${image}
      '';

      Restart = "always";
      # 5s was fast enough to march through repeated 68 GiB re-pins. Give the
      # host time to settle (and to get its page cache back) between tries.
      RestartSec = "20";
      TimeoutStopSec = "120";
    };
  };

  # ---- Checking what this actually resolved to -------------------------------
  #
  # The pool we asked for, the pool the engine took, the firmware carve-out and
  # the memory left over are all printed at startup:
  #
  #   journalctl --user -u halogen-flash-server 2>&1 \
  #     | grep -E '^(dmalloc|kv pool:|startup|slots:|checkpoint:)'
  #
  # ...and live, without touching anything:
  #
  #   curl -s localhost:8731/health | grep -o '"kv_pool_positions":[0-9]*'
  #   curl -s localhost:8731/health | grep -o '"vision":{[^}]*'
  #
  # NOTE ON MEMORY REPORTING: `free`/`MemAvailable` count this server's locked
  # weights as reclaimable page cache, so they overstate what this host has free
  # by roughly 68 GiB. The line to believe is the engine's own:
  #   "host memory left for everything else: ... GiB"
  #
  # BEFORE restarting: close the browser-heavy apps first, and as root
  #   echo 1 > /proc/sys/vm/compact_memory
  # Restarting against a fragmented host is the slow way to boot this thing.
  #
  # STILL SLOW TO IMPROVE FROM HERE (outside home-manager, needs root):
  #   1. BIOS: UMA frame buffer / dedicated graphics memory -> Auto (~512 MiB).
  #      We currently lose 2.0 GiB of RAM to a carve-out this server does not
  #      use (it drives the GPU through GTT), and the engine warns about it:
  #        "memory: 2.0 GiB of this machine's RAM is carved out for the iGPU in
  #         firmware ... it does not appear anywhere in /proc/meminfo"
  #      That GiB is file cache for the n-gram table, i.e. prefill speed.
  #   2. boot.kernelParams: amdgpu.gttsize + ttm.pages_limit up to ~99% of
  #      installed RAM (we are at 110 GiB of a 123.5 GiB machine; not binding
  #      today — headroom only). amd_iommu=off is already in place and is the
  #      one worth 13-16% of prefill.
  #   3. vm.swappiness=10, vm.page-cluster=0. Cannot be set from home manager
  #      (needs root); belongs in /etc/nixos/configuration.nix alongside the
  #      existing boot.kernelParams.
}
