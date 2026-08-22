{ pkgs }:
{
  hostname = "gmktec";
  username = "alexfneves";
  email = "alexfneves@gmail.com";
  isNixOS = true;
  useNixGL = false;
  enableLlm = true;
  enableNodejs = true;
  enableCleanNixEnv = false;
  # Which ollama backend to use:
  #   "rocm"   -> AMD ROCm acceleration
  #   "vulkan" -> Vulkan acceleration
  ollamaBackend = "vulkan";
  # Which ollama to run:
  #   "nixpkgs" -> nixpkgs-unstable build (stable, tested)
  #   "git"     -> latest from GitHub (bleeding edge, may crash — easy to flip back)
  ollamaSource = "git";
  # Which llama.cpp to run (llama-server + CLI tools). Two independent knobs:
  #   llamaSource -> "nixpkgs" (nixpkgs-unstable build, stable) or
  #                  "git"     (ROCmFPX fork from github:charlie12345/ROCmFPX)
  #   llamaBackend-> "vulkan" or "rocm"
  llamaSource = "git";
  llamaBackend = "vulkan";
  extraPackages = with pkgs; [
    steam
    obs-studio
    vlc
    proton-pass
    protonmail-desktop
    proton-vpn
    python3
  ];
}
