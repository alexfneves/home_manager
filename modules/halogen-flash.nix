{ pkgs, lib, hostConfig, ... }:
let
  # halogen-flash-server — a Strix Halo (gfx1151) engine built for exactly one
  # model, Qwen3.8-Flash-Next. Upstream:
  #   https://github.com/peonist-ai/halogen-flash-server
  #
  # Recommended deployment (from the upstream quickstart):
  #   weights repo   : peonist-ai/halogen-qwen3.8-flash-next  (public, ~130 GiB)
  #   weights folder : ~/halogen-models                       (mounted at /models)
  #   image          : see `image` below; upstream ships a :latest tag too, but
  #                    a moving engine under a model that changes its answers is
  #                    not worth it — the tag is pinned here.
  #
  # This server wants most of a 128 GB machine once it is loaded: the weights
  # stay resident and the KV pool is reserved up front.
  #
  # It is gated by `enableLlm` exactly like every other backend, so all of them
  # spawn together. Which ones you actually keep loaded at the same time is your
  # call, not something this config enforces — watch the pinned weights plus
  # whatever ollama and llama-server load alongside it. What this file does do
  # is put halogen first in the boot order and make it wait for memory rather
  # than start into a host that cannot give it the pin; see `Before` and
  # `preflightGate` below.
  llmEnabled = hostConfig.enableLlm;

  weightsRepo = "peonist-ai/halogen-qwen3.8-flash-next";

  # 0.18.9 (was 0.5.8). Two things this bump changes for us, both checked
  # against upstream's docs at the tag before pinning it:
  #
  #   * The KV pool is much cheaper than it was. 0.5.8 charged ~35.0 GiB for
  #     524,288 positions; 0.18.9 charges ~27 GB, so the pool we could not
  #     afford in September now fits inside the same budget. Every pool number
  #     in the pre-0.18 comments in this file was obsolete.
  #   * The default checkpoint is now `qwen38-flash-next-v2.hgn`, not w4b.
  #     Our volume holds w4b only, and the entrypoint falls back to it
  #     (`LEGACY_W4B=1`), so nothing changes on disk. Note the upgrade does
  #     NOT silently switch us to v2 — that takes the file plus an explicit
  #     HALOGEN_CHECKPOINT, and ~110 GiB of download.
  image = "ghcr.io/peonist-ai/halogen-flash-server:0.18.9";

  # ---- Tuning knobs --------------------------------------------------------
  #
  # HOW THESE REACH THE ENGINE. They go into a generated env file that the
  # `podman run` line passes with `--env-file`. They are NOT set via the unit's
  # `Environment=`, because a systemd unit's environment does not propagate
  # into a container — only explicit `--env`/`--env-file` flags do. Everything
  # in this block was dead for a month that way: the box was running pure image
  # defaults while this file described something else. If a knob here ever
  # seems ignored, confirm with:
  #
  #   podman inspect halogen-flash-server --format '{{range .Config.Env}}{{println .}}{{end}}' | grep HALOGEN
  #
  # CONTEXT IS NOT THE POOL — worth saying plainly, because conflating them
  # cost a debugging session. The context a single conversation may reach is
  # HALOGEN_CTX, which upstream sets to the model's full native 262,144 and
  # this file does not override. So 262k of context is already available to
  # any one conversation. The pool only decides how many such conversations
  # can be resident at the same time, because each reserves
  # `prompt + max_tokens` from it.
  #
  # THE POOL. Every in-flight conversation reserves `prompt + max_tokens`
  # positions from ONE pool shared by all slots; admission waits on it. The
  # pool takes RAM the page cache would otherwise spend on the model's n-gram
  # lookup table, which is read through the file cache and never held, so a
  # bigger pool means fewer cached rows and slower cold prompts. Per-stream
  # decode speed follows a conversation's own length, not the pool size.
  #
  # What 786432 buys, and why it fits. Upstream's own pool table for 0.18.9
  # (docs/configuration.md), with this checkpoint on this box:
  #
  #   pool 262,144  -> 19.8 GiB  one full conversation, or four at 65k
  #   pool 524,288  -> 27.0 GiB  two full, or four at 131k
  #   pool 786,432  -> 34.2 GiB  three full conversations        <- here
  #   pool 1,048,576-> 36.9 GiB  four full, but needs HALOGEN_MAX_TOK=16384
  #
  # Device budget = MemTotal - resident weights - hostReserveGiB:
  #   123.5 - 68.0 (w4b) - 18 (reserve) = 37.5 GiB
  #   34.2 (pool) + 1.5 (vision tower + scratch) = 35.7 GiB -> fits, ~1.8 to spare
  # Note it only fits at reserve 18. At 20 the budget is 35.5 and 786,432
  # misses by 0.2 GiB, so the fitter silently drops you to 524,288. That is
  # the whole reason those two numbers moved together here; do not tune one
  # without the other.
  #
  # CHECK IT AFTER THE FIRST START. The engine prints what it took:
  #   journalctl --user -u halogen-flash-server -b | grep -E 'kv pool:|device budget'
  # If it says LOWERING, this went the wrong way: drop back to 524288 rather
  # than shaving the reserve further.
  #
  # Throughput at any of these sizes (upstream-measured):
  #   1 stream alone ~41 t/s (speculative) | 4 streams ~76 total, 18.7 each
  #   | 8 streams ~85 total, 10.9 each; past 8 the total stops growing.
  kvPoolPositions = "786432";

  # Left free on top of the weights when the engine sizes the pool at startup.
  # Too little and the server starts, answers short prompts, then crawls on
  # long ones with the disk busy — that is the n-gram table being starved.
  # 18 is what 786,432 needs (see above). If long prompts start crawling,
  # this is the knob to raise — and the pool is the knob to lower with it.
  hostReserveGiB = "18";

  # Conversations generating at once. Not the memory knob (a slot is ~115 MB);
  # the pool is. Slots beyond what the pool can hold just queue. Kept at 4: it
  # matches the ~3-agent reality here and is where upstream tuned per-stream
  # speed. Raise to 6-8 to admit more clients at once instead of queueing
  # them, accepting ~11 t/s per stream at 8.
  kvSlots = "4";

  # The reply budget, in tokens, covering reasoning AND the answer.
  #
  # READ THIS BEFORE LOWERING THE CAP. The cap does not save memory. A request
  # over the cap is REJECTED, not shrunk — so a cap below what your clients
  # actually send converts working requests into 400s and frees nothing. This
  # is not theoretical: pi is configured with maxTokens 65536 for this model
  # (~/.pi/agent/models.json, providers/halogen/models[0] and
  # providers/pangolin/modelOverrides/halogen-qwen3.8-flash-next), and a cap
  # of 32768 broke a live 157k-token session with:
  #
  #   400: max_tokens 65536 exceeds this server's cap of 32768
  #
  # What DOES bound the reservation is the clamp, which landed in 0.18.4
  # (issue #178): a budget larger than the room the prompt leaves now runs in
  # that room instead of 400-ing, reported as timings.max_tokens_clamped_from
  # / _clamped_to and logged as `max_tokens clamped`. So near the context
  # ceiling a generous client budget is already safe, and the cap adds nothing
  # except the ability to break clients. Keep the cap at or above what clients
  # send. 65536 is upstream's default and matches pi exactly.
  #
  # If you ever genuinely want smaller reservations, change what pi ASKS for
  # (its maxTokens per model), not the server cap. That shrinks the actual
  # reservation; the cap only refuses it.
  #
  # The default is inert for pi and still worth setting: it only applies to
  # requests that name no budget, and 16384 is upstream's recommendation for
  # an agentic turn. It can never produce an error.
  maxTokensDefault = "16384";
  maxTokensCap = "65536";

  # 8-bit KV cache (0.18.9, opt-in). Keeps the attention cache in 8 bits
  # instead of 16, nearly halving it: a 524,288-position pool goes from
  # ~14.4 GiB of cache to ~8.2, and the whole device figure from ~27 GiB to
  # ~21. Prefill unchanged; decode ~0.2-0.6% slower short, ~1.7-1.9% at 32k.
  #
  # This is the lever that reaches "four full 262k conversations" without
  # cutting anything else. A 1,048,576-position pool is four full-length
  # conversations; at 16-bit it costs 36.9 GiB and additionally needs
  # HALOGEN_MAX_TOK=16384 (~9% off prefill) to fit alongside an 18 GiB
  # reserve. At 8-bit the same pool lands around 29 GiB and fits the 37.5 GiB
  # budget with real room, keeping MAX_TOK at 32768.
  #
  # LEFT OFF ON PURPOSE, not forgotten. With drafting on it is not
  # byte-identical to the 16-bit cache: perplexity moves -0.3% to +0.5% and
  # a long-context answer can differ. Retrieval of planted facts at 128k and
  # 250k scored the same as 16-bit, which is reassuring for agent work, but
  # it is still a change to what the model says rather than only how fast it
  # says it. Flip this to true if four resident 262k conversations matter
  # more than identical output, and note it cannot be combined with
  # HALOGEN_COMPOSABLE_CONTEXT=1. `/health` reports the format as
  # `kv_cache`: "bf16" or "int8".
  kv8 = false;

  # Keep the weights locked in RAM. The published decode speeds are measured
  # with this ON; `0` hands back a lot of memory and costs several times the
  # decode speed (6 t/s against 37 upstream). Also: it only applies to w4b —
  # v2 refuses 0 at startup. Only reach for it if another huge workload must
  # share this host.
  pinTrunk = "1";

  # Vision. `true` maps to HALOGEN_VISION_TOWER=1, which means "look for the
  # sidecar beside the checkpoint" — we have qwen38-flash-next-vision.hgn
  # there, so the tower loads. `false` makes the image path absent entirely
  # (upstream's default: images are a 400 naming the flag) and gives back the
  # ~2 GiB of tower + scratch, which is ~0.5 GiB more of n-gram page cache
  # at 1080p. Flip to false if nothing here actually sends images.
  visionEnabled = true;

  # The scratch scales with this cap, so it is the cheapest knob to turn if
  # the pool budget gets tight: upstream notes 4K reads no better than 1440p
  # and 1080p is plenty for text.
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

  # ---- The environment the container actually gets -------------------------
  #
  # One list, one file, one `--env-file`. Every knob above reaches the engine
  # through this and through nothing else. If you add a knob, add it here, and
  # confirm it landed with:
  #
  #   podman inspect halogen-flash-server --format '{{range .Config.Env}}{{println .}}{{end}}' | grep HALOGEN
  #
  # HALOGEN_KV_POOL_FIT=1 is deliberate: the engine measures the device budget
  # at startup and lowers the pool rather than failing the start. Asking for
  # 524288 with the fitter on degrades gracefully; asking for it with the
  # fitter off risks a hard allocation failure mid-boot.
  halogenEnv =
    [
      "HALOGEN_API_PORT=8731"
      "HALOGEN_KV_POOL_POSITIONS=${kvPoolPositions}"
      "HALOGEN_KV_POOL_FIT=1"
      "HALOGEN_HOST_RESERVE_GIB=${hostReserveGiB}"
      "HALOGEN_KV_SLOTS=${kvSlots}"
      "HALOGEN_MAX_TOKENS_DEFAULT=${maxTokensDefault}"
      "HALOGEN_MAX_TOKENS_CAP=${maxTokensCap}"
      "HALOGEN_FLASH_PIN_TRUNK=${pinTrunk}"
    ]
    ++ lib.optionals visionEnabled [
      "HALOGEN_VISION_TOWER=1"
      "HALOGEN_VISION_MAX_PIXELS=${visionMaxPixels}"
    ]
    ++ lib.optionals kv8 [ "HALOGEN_KV8=1" ]
    ++ lib.optionals halogenDownload [ "HALOGEN_DOWNLOAD=${weightsRepo}" ];

  halogenEnvFile = pkgs.writeText "halogen-flash.env" (lib.concatStringsSep "\n" halogenEnv + "\n");

  # ---- Pre-flight: do not start into a host that cannot give us the pin ----
  #
  # WHY THIS EXISTS. The engine refuses to pin when MemAvailable is under
  # `payload + a 16 GiB floor`, because pinned pages cannot be swapped and a
  # task waiting on them cannot be killed, so over-pinning wedges the machine
  # for minutes instead of failing. On Sep 16 that gate closed and the unit,
  # set to restart forever with no rate limit, restarted 1,246 times in ~11
  # hours (~120/hour) while the desktop held the RAM. Each attempt was loud in
  # the journal and invisible in practice.
  #
  # Waiting is the honest behaviour here: memory frees up when the thing
  # holding it exits, and then halogen can start. So poll, say so, and give up
  # with a message that names the number rather than an exit code nobody reads.
  # This is not a crash guard and does not replace thinking about what runs
  # beside halogen — it turns a silent restart loop into a legible wait.
  #
  # The 83600 MiB is w4b-specific: 65.64 GiB of pinnable payload plus the
  # engine's 16.00 GiB floor = 81.64 GiB = 83,600 MiB. v2 needs less; if the
  # volume changes to v2, re-read the "refusing to pin" line for the new
  # payload figure and lower this with it.
  preflightGate = true;
  preflightMinMemMiB = 83600;
  preflightWaitSec = 600;

  preflightScript = pkgs.writeShellScript "halogen-preflight" ''
    need=${toString preflightMinMemMiB}
    deadline=${toString preflightWaitSec}
    step=15
    elapsed=0
    while :; do
      avail_kb=$(${pkgs.gawk}/bin/awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
      avail_mib=$((avail_kb / 1024))
      if [ "$avail_mib" -ge "$need" ]; then
        if [ "$elapsed" -gt 0 ]; then
          echo "preflight: MemAvailable recovered to $avail_mib MiB after ''${elapsed}s, starting"
        else
          echo "preflight: MemAvailable $avail_mib MiB >= $need MiB, starting"
        fi
        exit 0
      fi
      if [ "$elapsed" -ge "$deadline" ]; then
        echo "preflight: NOT starting. MemAvailable is $avail_mib MiB; the weight pin needs $need MiB."
        echo "preflight: the engine will refuse to pin below that (pinned pages cannot be swapped,"
        echo "           and a task waiting on them cannot be killed), and it is right to."
        echo "preflight: free some memory - a browser, a loaded ollama/llama-server model, a"
        echo "           second desktop session - and this unit comes up on its own next retry."
        echo "preflight: as root, 'echo 1 > /proc/sys/vm/compact_memory' helps if the RAM is"
        echo "           free but fragmented rather than used."
        exit 1
      fi
      echo "preflight: MemAvailable $avail_mib MiB < $need MiB, waiting ($elapsed of $deadline s)"
      ${pkgs.coreutils}/bin/sleep $step
      elapsed=$((elapsed + step))
    done
  '';

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

      # Start before the other LLM backends. All three are enabled on this box
      # by the same `enableLlm` flag and halogen is the one that needs ~66 GiB
      # pinned in large contiguous chunks, so it should win that race rather
      # than arrive after ollama and llama-server have taken pages. Ordering
      # only, no dependency: if they are not enabled this is inert, and if
      # halogen's gate holds, they still start.
      Before = [ "llama-server.service" "ollama.service" ];

      # A crash loop here is not a cheap crash loop: every restart re-pins ~68
      # GiB of weights and re-reads them through the page cache, and a re-pin
      # that fights a fragmented host can burn tens of minutes at 100% of one
      # core. A rate limit is left OFF deliberately (0.17's "let halogen try to
      # recover by himself") so a transient failure self-heals rather than
      # leaving the model down. The pre-flight gate above is what keeps that
      # loop legible now: it waits for memory instead of hammering, so the
      # failure mode is "waiting, N of 600 s" in the journal rather than 1,246
      # anonymous restarts. Re-enable this only if you want halogen to stop
      # trying rather than keep trying.
      # StartLimitIntervalSec = 900;
      # StartLimitBurst = 3;
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
      # HALOGEN's OWN SETTINGS ARE NOT SET HERE — see halogenEnv above. A
      # systemd unit's `Environment=` is not inherited by a container, so every
      # HALOGEN_* variable that used to live here was silently dropped and the
      # server ran pure image defaults for a month. They go in via --env-file.
      Environment = [
        "PATH=${pkgs.podman}/bin:/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin"
      ];

      # Gate first (cheap, and it is the thing that should stop us), then the
      # best-effort image refresh. The leading "-" on the pull keeps a network
      # failure from taking the start down; the gate is fatal on purpose.
      ExecStartPre =
        lib.optionals preflightGate [ preflightScript ]
        ++ lib.optionals pullImage [ "-${pkgs.podman}/bin/podman pull ${image}" ];

      ExecStart = pkgs.writeShellScript "halogen-flash-server" ''
        exec ${pkgs.podman}/bin/podman run --rm --replace \
          --name halogen-flash-server \
          --env-file ${halogenEnvFile} \
          --publish 127.0.0.1:8731:8731 \
          --device /dev/kfd \
          --device /dev/dri \
          --group-add keep-groups \
          --security-opt seccomp=unconfined \
          --ipc=host \
          --ulimit memlock=-1:-1 \
          --volume "$HOME/halogen-models:/models${modelsMountOpt}" \
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
  #   curl -s localhost:8731/health | grep -o '"kv_cache":"[a-z0-9]*"'   # bf16 or int8 (kv8)
  #   curl -s localhost:8731/health | grep -o '"vision":{[^}]*'
  #   curl -s localhost:8731/health | grep -o '"max_tokens_default":[0-9]*'
  #
  # and that the file we generated is what the container was handed:
  #
  #   podman inspect halogen-flash-server --format '{{range .Config.Env}}{{println .}}{{end}}' | grep HALOGEN
  #
  # NOTE ON MEMORY REPORTING: `free`/`MemAvailable` count this server's locked
  # weights as reclaimable page cache, so they overstate what this host has free
  # by roughly 68 GiB, and htop's "used" excludes page cache entirely and
  # therefore understates halogen by roughly the same amount. The two numbers
  # that are honest here are the engine's own
  #   "host memory left for everything else: ... GiB"
  # and the cgroup:
  #   podman stats --no-stream halogen-flash-server
  #
  # BEFORE restarting: close the browser-heavy apps first, and as root
  #   echo 1 > /proc/sys/vm/compact_memory
  # Restarting against a fragmented host is the slow way to boot this thing.
  # The pre-flight gate is checked against MemAvailable, which is the number
  # to watch: at the w4b layout it needs 81.64 GiB and a desktop session that
  # has been up a while usually leaves 78-80, which is why a mid-session
  # restart is the risky one and a cold boot is not.
  #
  # OUTSIDE HOME-MANAGER (needs root). Status against /etc/nixos/configuration.nix,
  # read on 2026-10-18, not carried over from old comments in this file:
  #
  #   ALREADY DONE — do not repeat:
  #     * amd_iommu=off, plus ttm/amdttm pages_limit and page_pool_size at
  #       28,835,840 pages (110 GiB). The old note asking for these was stale;
  #       they are in boot.kernelParams already, and amd_iommu=off is the one
  #       worth a double-digit percentage of prefill.
  #     * linger = true, which is what lets default.target bring this unit up
  #       ahead of the graphical session.
  #
  #   NOT DONE, AND NOT WORTH THE REBUILD:
  #     * vm.swappiness=10 / vm.page-cluster=0. Carried in old comments as if
  #       outstanding. They are not set (60 / 3 today), but swap has been at
  #       0 B used across every check we made, so the reclaim behaviour they
  #       would change is not being exercised. A speculative tuning on a box
  #       that is not swapping. Skip unless swap actually gets used and something
  #       stalls on it.
  #
  #   STILL WORTH IT, AND NOT A NIX CHANGE:
  #     * BIOS: UMA frame buffer / dedicated graphics memory -> Auto (~512 MiB).
  #       ~2.0 GiB is carved out for the iGPU in firmware and invisible to
  #       /proc/meminfo; halogen drives the GPU through GTT and does not use
  #       it. That GiB would go to the n-gram page cache, i.e. prefill speed.
  #       The engine warns about it at startup.
}
