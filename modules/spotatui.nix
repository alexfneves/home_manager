{ config, lib, pkgs, ... }:
let
  # Use the (possibly nixGL-wrapped) alacritty from programs.alacritty so the
  # launcher keeps working on both NixOS and Ubuntu hosts.
  alacritty = lib.getExe config.programs.alacritty.package;
  spotatui = lib.getExe pkgs.spotatui;

  # Dedicated launcher: run spotatui inside Alacritty. The terminal.shell
  # override (herdr-cycle) is bypassed by passing -e. WM_CLASS is overridden
  # per-instance (-o) so KDE's taskbar/launcher treat this window as Spotatui
  # (Spotify icon) instead of an Alacritty window.
  spotatuiLauncher = pkgs.writeShellScriptBin "spotatui-launcher" ''
    exec ${alacritty} \
      -o 'window.class.instance="Spotatui"' \
      -o 'window.class.general="Spotatui"' \
      -e ${spotatui}
  '';
in
{
  home.packages = [ spotatuiLauncher ];

  # Show up in the KDE application launcher / start menu.
  xdg.desktopEntries."spotatui" = {
    name = "Spotatui";
    comment = "Spotify client in the terminal";
    exec = "${lib.getExe spotatuiLauncher}";
    # Absolute store path to Spotify's own icon so KDE always renders it,
    # regardless of icon-theme lookup or XDG_DATA_DIRS setup.
    icon = "${pkgs.spotify}/share/icons/hicolor/512x512/apps/spotify-client.png";
    terminal = false;
    type = "Application";
    categories = [ "Audio" "AudioVideo" "Music" ];
    settings.StartupWMClass = "Spotatui";
  };
}