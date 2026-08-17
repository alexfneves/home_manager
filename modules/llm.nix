{ pkgs, lib, unstablePkgs, ollamaGit, ollamaVulkan, hostConfig, ... }:
let
  backend = hostConfig.ollamaBackend or "rocm";
  source  = hostConfig.ollamaSource or "nixpkgs";
  isRocm = backend == "rocm";
  isVulkan = backend == "vulkan";
  # All four combos: backend (rocm/vulkan) x source (nixpkgs/git)
  ollamaPackage =
    if source == "git" then
      ollamaGit backend          # latest from GitHub, same backend
    else if isVulkan then
      ollamaVulkan               # stable nixpkgs-unstable build
    else
      unstablePkgs.ollama-rocm;  # stable nixpkgs-unstable build
  ollamaEnv = if isRocm then {
      # HSA_OVERRIDE_GFX_VERSION = "11.0.0";
      # OLLAMA_LLM_LIBRARY = "rocm";
      # HSA_OVERRIDE_GFX_VERSION = "11.5.1";
      # HCC_AMDGPU_TARGET = "gfx1151";
      # GGML_ROCM_ENABLE_UNIFIED_MEMORY = "1";
      # Tell ROCm to aggressively utilize unified system memory
      HSA_AMD_SYSTEM_RESOURCES = "1";
      HSA_ENABLE_SDMA = "0";
    } else if isVulkan then {
      OLLAMA_VULKAN = "1";
    } else {};
  needKfdWait = isRocm;
in
{
  # ---- LLM stack (home machine only: hostConfig.enableLlm) ----
  services.ollama = lib.mkIf hostConfig.enableLlm {
    enable = true;
    # home-manager's option only accepts null/false/"rocm"/"cuda" — it exists
    # to override the package's acceleration. We already pass a backend-correct
    # package, so for vulkan we leave it null (the vulkan build's wrapper sets
    # OLLAMA_VULKAN=1) and keep "rocm" only for the rocm builds.
    acceleration = if isRocm then "rocm" else null;
    package = ollamaPackage;
    # For Strix Halo (gfx1150/1151), we still need the spoof
    # to make the ROCm stack recognize the brand-new iGPU
    host = "0.0.0.0"; # Allows connections from other devices
    environmentVariables = ollamaEnv;
  };
  # systemd.user.services.ollama.Install.WantedBy = [ "basic.target" ];
  systemd.user.services.ollama = lib.mkIf hostConfig.enableLlm {
    Install.WantedBy = [ "graphical-session.target" ];
    Service.After = [ "graphical-session.target" ];
    Service.Restart = "always";
    Service.RestartSec = "3";
    Service.ExecStartPre = lib.optional needKfdWait (pkgs.writeShellScript "ollama-wait-kfd" ''
        for i in 1 2 3 4 5; do
          [ -e /dev/kfd ] && exit 0 || sleep 1
        done
        exit 0
      '');
    Service.Environment =
      [
        "OLLAMA_NUM_PARALLEL=4"
        "OLLAMA_MAX_LOADED_MODELS=4" # Allows up to 4 models in memory at once
        # "OLLAMA_CONTEXT_LENGTH=64000"
        "OLLAMA_CONTEXT_LENGTH=128000"
        "OLLAMA_FLASH_ATTENTION=1"
      ]
      # Strix Halo's iGPU is dropped by ollama for Vulkan: its default-allowlist
      # (discover/runner.go, defaultIntegratedROCmGFXTargets) only covers the
      # ROCm path (gfx1151), and Vulkan integrated GPUs are never allowed by
      # default. ROCm on this chip needs no such override, so gate it on vulkan.
      ++ lib.optionals isVulkan [ "OLLAMA_IGPU_ENABLE=1" ];
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
