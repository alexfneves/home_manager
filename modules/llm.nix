{ pkgs, lib, unstablePkgs, hostConfig, ... }:
{
  # ---- ROCm / LLM stack (home machine only: hostConfig.enableLlm) ----
  services.ollama = lib.mkIf hostConfig.enableLlm {
    enable = true;
    acceleration = "rocm";
    package = unstablePkgs.ollama-rocm;
    # package = pkgs.ollama-rocm;
    # For Strix Halo (gfx1150/1151), we still need the spoof
    # to make the ROCm stack recognize the brand-new iGPU
    host = "0.0.0.0"; # Allows connections from other devices
    environmentVariables = {
      # HSA_OVERRIDE_GFX_VERSION = "11.0.0";
      # OLLAMA_LLM_LIBRARY = "rocm";
      # HSA_OVERRIDE_GFX_VERSION = "11.5.1";
      # HCC_AMDGPU_TARGET = "gfx1151";
      # GGML_ROCM_ENABLE_UNIFIED_MEMORY = "1";
      # Tell ROCm to aggressively utilize unified system memory
      HSA_AMD_SYSTEM_RESOURCES = "1";
      HSA_ENABLE_SDMA = "0";
    };
  };
  # systemd.user.services.ollama.Install.WantedBy = [ "basic.target" ];
  systemd.user.services.ollama = lib.mkIf hostConfig.enableLlm {
    Install.WantedBy = [ "graphical-session.target" ];
    Service.Environment = [
      "OLLAMA_NUM_PARALLEL=4"
      "OLLAMA_MAX_LOADED_MODELS=4" # Allows up to 4 models in memory at once
      # "OLLAMA_CONTEXT_LENGTH=64000"
      "OLLAMA_CONTEXT_LENGTH=128000"
      "OLLAMA_FLASH_ATTENTION=1"
    ];
  };
  systemd.user.services.open-webui = lib.mkIf hostConfig.enableLlm {
    Unit = {
      Description = "Open WebUI";
      # After = [ "ollama.service" ];
      # Requires = [ "ollama.service" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
      # WantedBy = [ "basic.target" ];
    };
    Service = {
      Environment = [
        "OLLAMA_API_BASE_URL=http://127.0.0.1:11434"
        "DATA_DIR=%h/.local/share/open-webui"
        "WEBUI_AUTH=False"
        # Point the app to the local writable copy
        "FRONTEND_BUILD_DIR=%h/.local/share/open-webui/static"
        "HOST=0.0.0.0"
      ];
      # 1. Create the data dir
      # 2. Copy static files to a writable location so the app stops complaining
      ExecStartPre = pkgs.writeShellScript "open-webui-prep" ''
        ${pkgs.coreutils}/bin/mkdir -p "$HOME/.local/share/open-webui/static"
        ${pkgs.coreutils}/bin/cp -rn ${pkgs.open-webui}/lib/python3.13/site-packages/open_webui/static/* "$HOME/.local/share/open-webui/static/"
        ${pkgs.coreutils}/bin/chmod -R +w "$HOME/.local/share/open-webui/static"
      '';
      ExecStart = "${pkgs.open-webui}/bin/open-webui serve";
      Restart = "always";
    };
  };
}
