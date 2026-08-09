{ pkgs, lib, hostConfig, unstablePkgs, ... }:
{
  # All packages, including machine-specific additions.
  home.packages = with pkgs; [
    baobab
    devenv
    ffmpeg # pi-listen
    nodejs # pi
    cachix
    sshs
    direnv
    pinta
    devbox
    shfmt
    meld
    pdfarranger
    yazi
    eza
    bat
    fzf
    fd
    htop
    nvtopPackages.full
    gitFull
    starship
    nerd-fonts.jetbrains-mono
    zsh-syntax-highlighting
    zsh-fast-syntax-highlighting
    zsh-autocomplete
    zsh-nix-shell
    zsh-z
    lazygit
    gitui
    lf
    lldb
    sshfs
    firefox
    vscode
    inotify-tools
    xclip
    nix-tree
    proton-pass
    protonmail-desktop
    protonvpn-gui
    uv
    python3
    steam
    obs-studio
    vlc
    wget
    ncdu
    podman
    distrobox
    spotatui
    unstablePkgs.herdr
  ]
  # Machine-specific packages (ROCm/LLM stack, etc.)
  ++ (if hostConfig.enableLlm then with pkgs; [
    unstablePkgs.llama-cpp-rocm
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
    open-webui
  ] else [])
  ++ hostConfig.extraPackages
  ++ hostConfig.extraUnstablePkgs;
}
