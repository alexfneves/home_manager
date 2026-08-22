{ pkgs, lib, unstablePkgs, llamaPackage, hostConfig, ... }:
{
  # llama-server (llama.cpp router server) — LLM host only.
  #
  # This wraps what used to live in ~/models/serve.bash:
  #   llama-server --models-preset ~/.config/llama-server/models.ini --host 127.0.0.1 --port 8001
  #
  # The presets file (models.ini) is kept in this repo at ./llama-server/models.ini
  # and symlinked to ~/.config/llama-server/models.ini via activation (see
  # activation.nix), so model paths / sampling params can be edited without a
  # rebuild. The actual GGUF files stay outside nix, in ~/models.
  #
  # Leftover options from the serve.bash experiments (currently disabled there
  # too, so deliberately not enabled here):
  #   --models-dir ~/models --models-max 2 --sleep-idle-seconds 300
  systemd.user.services.llama-server = lib.mkIf hostConfig.enableLlm {
    Unit = {
      Description = "llama.cpp router server (models.ini presets)";
      After = [ "graphical-session.target" ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
    Service = {
      # %h -> $HOME; the build matches the llama.cpp variant in home.packages
      # (llamaSource: "nixpkgs"|"git" x llamaBackend: "vulkan"|"rocm")
      ExecStart = "${llamaPackage}/bin/llama-server --models-preset %h/.config/llama-server/models.ini --host 127.0.0.1 --port 8001";
      Restart = "always";
      RestartSec = "3";
    };
  };
}
