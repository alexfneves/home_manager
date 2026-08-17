{ pkgs, lib, hostConfig, config, ... }:
let
  nixGLWrap = pkg: pkgs.runCommand "${pkg.name}-nixgl-wrapper" {} ''
    mkdir $out
    ln -s ${pkg}/* $out
    rm $out/bin
    mkdir $out/bin
    for bin in ${pkg}/bin/*; do
     wrapped_bin=$out/bin/$(basename $bin)
     echo "exec ${lib.getExe pkgs.nixgl.nixGLIntel} $bin \$@" > $wrapped_bin
     chmod +x $wrapped_bin
    done
  '';
in
{
  programs.alacritty = {
    enable = true;
    # On Ubuntu/old-GPU machines the GL stack lives outside Nix, so wrap
    # through nixGL. On NixOS (home machine) use the plain binary.
    package = if hostConfig.useNixGL then nixGLWrap pkgs.alacritty else pkgs.alacritty;
    settings = {
      window = {
        startup_mode = "Maximized";
      };
      terminal.shell = {
        # herdr-cycle: fresh session, or attach/delete menu (see
        # herdr/herdr-cycle.sh, symlinked to ~/.local/bin by activation.nix).
        # Absolute path so no PATH assumptions are needed here.
        program = "${config.home.homeDirectory}/.local/bin/herdr-cycle";
      };
      font = {
        normal = {
          family = "JetBrainsMono Nerd Font Mono";
          style = "Regular";
        };
      };
      colors = {
        # https://github.com/catppuccin/alacritty/blob/main/catppuccin-latte.toml

        primary = {
          background = "#EFF1F5";
          foreground = "#4C4F69";
          dim_foreground = "#4C4F69";
          bright_foreground = "#4C4F69";
        };
        cursor = {
          text = "#EFF1F5";
          # cursor = "#DC8A78";
          cursor = "#008080";
        };
        vi_mode_cursor = {
          text = "#EFF1F5";
          cursor = "#7287FD";
        };
        search.matches = {
          foreground = "#EFF1F5";
          background = "#6C6F85";
        };
        search.focused_match = {
          foreground = "#EFF1F5";
          background = "#40A02B";
        };
        footer_bar = {
          foreground = "#EFF1F5";
          background = "#6C6F85";
        };
        hints.start = {
          foreground = "#EFF1F5";
          background = "#DF8E1D";
        };
        hints.end = {
          foreground = "#EFF1F5";
          background = "#6C6F85";
        };
        selection = {
          text = "#EFF1F5";
          background = "#DC8A78";
        };
        normal = {
          black = "#5C5F77";
          red = "#D20F39";
          green = "#40A02B";
          yellow = "#DF8E1D";
          blue = "#1E66F5";
          magenta = "#EA76CB";
          cyan = "#179299";
          white = "#ACB0BE";
        };
        bright = {
          black = "#6C6F85";
          red = "#D20F39";
          green = "#40A02B";
          yellow = "#DF8E1D";
          blue = "#1E66F5";
          magenta = "#EA76CB";
          cyan = "#179299";
          white = "#BCC0CC";
        };
        dim = {
          black = "#5C5F77";
          red = "#D20F39";
          green = "#40A02B";
          yellow = "#DF8E1D";
          blue = "#1E66F5";
          magenta = "#EA76CB";
          cyan = "#179299";
          white = "#ACB0BE";
        };
        indexed_colors = [
          {
            index = 16;
            color = "#FE640B";
          }
          {
            index = 17;
            color = "#DC8A78";
          }
        ];
      };
    };
  };
}
