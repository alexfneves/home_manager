{ pkgs, lib, unstablePkgs, llamaPackage, hostConfig, ... }:
let
  # Starts with the rest of the LLM stack — no longer gated on halogen. Running
  # llama-server alongside halogen is a memory-budget decision the operator
  # makes per host, not something this module enforces (see halogen-flash.nix).
  llmEnabled = hostConfig.enableLlm;
in
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
  systemd.user.services.llama-server = lib.mkIf llmEnabled {
    Unit = {
      Description = "llama.cpp router server (models.ini presets)";
      After = [ "graphical-session.target" ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
    Service = {
      # %h -> $HOME; the build matches the llama.cpp variant in home.packages
      # (llamaSource: "nixpkgs"|"rocmfpx"|"ggml-org"|"k2horizon"|"dflash2" x llamaBackend: "vulkan"|"rocm")
      ExecStart = "${llamaPackage}/bin/llama-server --models-preset %h/.config/llama-server/models.ini --host 127.0.0.1 --port 8001";
      # Strix Halo is a UMA APU: let HIP use the unified memory pool.
      # HSA_OVERRIDE_GFX_VERSION is required per the ROCmFP4 model cards.
      Environment = [
        "GGML_HIP_ENABLE_UNIFIED_MEMORY=1"
        "HSA_OVERRIDE_GFX_VERSION=11.5.1"
      ];
      Restart = "always";
      RestartSec = "3";
    };
  };
}
