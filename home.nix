{ config, pkgs, lib, inputs, ... }:
let
  # ...
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
  # Home Manager needs a bit of information about you and the
  # paths it should manage.

  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    baobab
    inputs.devenv.packages."${pkgs.system}".devenv
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
    gitFull
    spotify
    starship
    nerdfonts
    zsh-syntax-highlighting
    zsh-fast-syntax-highlighting   
    zsh-autocomplete
    zsh-nix-shell
    zsh-z
    lazygit
    gitui
    lf
    # clang
    # clang-tools
    lldb
    sshfs
    # google-chrome
    firefox
    vscode
    # python310
    # python310Packages.python-lsp-server
    # python310Packages.debugpy
    inotify-tools
    xclip
    nix-tree
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "24.11";

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
  programs.alacritty = {
	  enable = true;
	  package = nixGLWrap pkgs.alacritty;   
    settings = {
      window = {
        startup_mode = "Maximized";
      };
      terminal.shell = {
        program = "zsh";
        args = ["-l" "-c" "zellij"];
      };
      font = {
        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Medium";
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
  programs.starship.enable = true;
  targets.genericLinux.enable = true;

  # zsh autcomplete from https://tesar.tech/blog/2024-10-21_nix_os_zsh_autocomplete
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    enableCompletion = false;
    completionInit = "autoload -U compinit && compinit -u";
    shellAliases = {
      j = "cd $(fd -H -t d . ~ | fzf)";
      e = "j && hx";
      g = "lazygit";
      gl = "git log --graph --decorate --pretty=oneline --abbrev-commit --all";
      gk = "gitk --all";
      gg = "git gui";
      za = "alacritty --command \"zellij a $(zellij list-sessions | fzf)\"";
      u = "home-manager switch";
      mount = "host=$(cat ~/.ssh/config | grep -oP \"(?<=Host\\s)[^\\s]+\" | fzf) && mkdir -p /tmp/fs/\"$host\" && sshfs \"$host\": \"/tmp/fs/$host\"";
      # unmount = "fusermount -u /tmp/fs/\"$(ls /tmp/fs/ | fzf)\"";
      unmount = "host=$(ls /tmp/fs/ | fzf) && echo \"$host\" && fusermount -u /tmp/fs/\"$host\" && rmdir /tmp/fs/\"$host\"";
    };
    initExtra = ''
      bindkey "^[[A" up-line-or-search
      bindkey "^[[1;5C" forward-word
      bindkey "^[[1;5D" backward-word
      bindkey  "^[[H"   beginning-of-line
      bindkey  "^[[F"   end-of-line
      bindkey  "^[[3~"  delete-char
      # bindkey -s "^A" "ls^M"

      source ~/.zsh_aliases
      PATH=/home/$USER/.local/bin:$PATH
    '';
    
    plugins = [
      {
        name = "fast-syntax-highlighting";
        file = "fast-syntax-highlighting.plugin.zsh";
        src = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/site-functions";
      }
      {
        name = "zsh-nix-shell";
        file = "nix-shell.plugin.zsh";
        src = "${pkgs.zsh-nix-shell}/share/zsh-nix-shell";
      }
      {
        name = "zsh-autocomplete"; # completes history, commands, etc.
        src = pkgs.fetchFromGitHub {
          owner = "marlonrichert";
          repo = "zsh-autocomplete";
          rev = "762afacbf227ecd173e899d10a28a478b4c84a3f";
          sha256 = "1357hygrjwj5vd4cjdvxzrx967f1d2dbqm2rskbz5z1q6jri1hm3";
        }; # e.g., nix-prefetch-url --unpack https://github.com/marlonrichert/zsh-autocomplete/archive/762afacbf227ecd173e899d10a28a478b4c84a3f.tar.gz
      }
    ];

    oh-my-zsh = {
      enable = true;
      plugins = [ "z" ];
      extraConfig = ''
                # Required for autocomplete with box: https://unix.stackexchange.com/a/778868
                zstyle ':completion:*' completer _expand _complete _ignored _approximate _expand_alias
                zstyle ':autocomplete:*' default-context curcontext 
                zstyle ':autocomplete:*' min-input 0

                setopt HIST_FIND_NO_DUPS

                autoload -Uz compinit
                compinit

                setopt autocd  # cd without writing 'cd'
                setopt globdots # show dotfiles in autocomplete list
      '';
    };
  };

  home.file.".zsh_aliases".source = ./.zsh_aliases;

  programs.git.package = pkgs.gitFull;
  programs.git = {
    enable = true;
    userName  = "Alex Fernandes Neves";
    userEmail = "afn@blue-ocean-robotics.com";
  };

  programs.zellij = {
    enable = true;
  };
  xdg.configFile."zellij".source = ./zellij;

  programs.helix = {
    enable = true;
    package = pkgs.helix;
    settings = {
      theme = "catppuccin_latte";
      editor = {
        line-number = "relative";
        auto-save = true;
        bufferline = "multiple";
        color-modes = true;
      };
      editor.cursor-shape = {
        insert = "bar";
        normal = "block";
        select = "underline";
      };
      editor.file-picker.hidden = false;
      keys.normal = {
        "tab" = ":bn";
        "S-tab" = ":bp";
      };
      editor.whitespace.render.tab = "all";
      editor.indent-guides.render = true;
      editor.soft-wrap.enable = true;
      keys.normal = {
      #   space.space = "file_picker";
      #   space.w = ":w";
      #   space.q = ":q";
        esc = [ "collapse_selection" "keep_primary_selection" ];
      };
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
