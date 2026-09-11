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
  # The weights are fetched by the container itself on first start
  # (HALOGEN_DOWNLOAD), the way the upstream quickstart does it: it resumes
  # partial transfers, so an interrupted download continues where it stopped.
  # That is deliberate here — a separate host-side download unit is a `oneshot`
  # and would make `home-manager switch` / login block until ~130 GiB are in,
  # while a container is `Type=simple` and starts (and keeps downloading) in the
  # background.
  #
  # This server wants most of a 128 GB machine once it is loaded: the weights
  # stay resident and the KV pool is reserved up front. That is why flipping
  # `enableHalogen` on (hosts/gmktec.nix) turns the ollama / open-webui /
  # llama-server stack off instead (see modules/llm.nix and llama-server.nix).
  # Set `enableHalogen = false` to get the old stack back.
  halogenEnabled = hostConfig.enableHalogen or false;
  enabled = hostConfig.enableLlm && halogenEnabled;

  weightsRepo = "peonist-ai/halogen-qwen3.8-flash-next";
  image = "ghcr.io/peonist-ai/halogen-flash-server:0.5.8";
in
{
  # Run the server. Rootless podman, one container ("all" mode): the engine
  # binds loopback inside the container and the OpenAI-compatible front-end is
  # published on :8731.
  #
  #   - HALOGEN_DOWNLOAD writes the recommended repo into /models (i.e.
  #     ~/halogen-models) on first start, so the volume is mounted read-WRITE.
  #     Drop HALOGEN_DOWNLOAD and add ":ro" once the weights are in place if you
  #     want later starts to make no outbound connections at all.
  #   - HALOGEN_VISION_TOWER=1 loads the vision sidecar that ships beside the
  #     checkpoint, so /v1/chat/completions accepts images (text is unchanged).
  systemd.user.services.halogen-flash-server = lib.mkIf enabled {
    Unit = {
      Description = "halogen-flash server (Qwen3.8-Flash-Next, OpenAI API :8731)";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      # systemd gives user units a minimal PATH; the nixpkgs podman needs its
      # helper wrapper (crun/conmon) and the setuid newuidmap/newgidmap helpers
      # in /run/wrappers/bin for rootless operation.
      Environment = [
        "PATH=${pkgs.podman}/bin:/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin"
      ];
      # Refresh the image when the network is up; a failure here is not fatal
      # (leading "-"), the cached image still runs.
      ExecStartPre = "-${pkgs.podman}/bin/podman pull ${image}";
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
          --env HALOGEN_API_PORT=8731 \
          --env HALOGEN_DOWNLOAD=${weightsRepo} \
          --env HALOGEN_VISION_TOWER=1 \
          --volume "$HOME/halogen-models:/models" \
          ${image}
      '';
      Restart = "always";
      RestartSec = "5";
      TimeoutStopSec = "120";
    };
  };
}
