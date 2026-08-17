{ pkgs }:
{
  hostname = "gmktec";
  username = "alexfneves";
  email = "alexfneves@gmail.com";
  isNixOS = true;
  useNixGL = false;
  enableLlm = true;
  # Which ollama backend to use:
  #   "rocm"   -> AMD ROCm acceleration
  #   "vulkan" -> Vulkan acceleration
  ollamaBackend = "vulkan";
  # Which ollama to run:
  #   "nixpkgs" -> nixpkgs-unstable build (stable, tested)
  #   "git"     -> latest from GitHub (bleeding edge, may crash — easy to flip back)
  ollamaSource = "git";
  extraPackages = with pkgs; [
    steam
    obs-studio
    vlc
    proton-pass
    protonmail-desktop
    proton-vpn
    nvtopPackages.full
  ];
}
