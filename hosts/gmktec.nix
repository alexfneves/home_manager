{ pkgs }:
{
  hostname = "gmktec";
  username = "alexfneves";
  email = "alexfneves@gmail.com";
  isNixOS = true;
  useNixGL = false;
  enableLlm = true;
  enableNodejs = true;
  # Which ollama-rocm to run:
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
    python3
  ];
}
