{ config, pkgs, lib, inputs, hostConfig, ... }:
{
  # Split across modules/ — import everything here so one file stays the
  # single entry point. Each module lives in modules/ and receives the
  # special args (hostConfig, unstablePkgs) from flake.nix automatically.
  imports = [
    ./modules/packages.nix
    ./modules/spotatui.nix
    ./modules/programs.nix
    ./modules/shell/zsh.nix
    ./modules/shell/starship.nix
    ./modules/shell/direnv.nix
    ./modules/shell/btop.nix
    ./modules/editors/helix.nix
    ./modules/editors/alacritty.nix
    ./modules/git.nix
    ./modules/llm.nix
    ./modules/llama-server.nix
    ./modules/session.nix
    ./modules/activation.nix
    ./modules/clean-nix-for-ubuntu.nix
  ];

  # ---- Global config (applies to every machine) ----
  fonts.fontconfig.enable = true;

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "26.05";

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };

  targets.genericLinux.enable = !hostConfig.isNixOS;

  nix.gc = {
    automatic = true;
    dates = "weekly";  # <-- This replaces 'frequency'
    options = "--delete-older-than 14d";
  };
}
