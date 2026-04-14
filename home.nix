{ config, pkgs, unstablePkgs, lib, inputs, ... }:
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
  # Home Manager needs a bit of information about you and the
  # paths it should manage.

  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    baobab
    devenv
    # inputs.llm-agents.packages.${pkgs.system}.pi
    ffmpeg # pi-listen
    nodejs # pi
    # (pkgs.llama-cpp.override { cudaSupport = true; })
    open-webui
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
    spotify
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
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.11";

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
  programs.brave.enable = true;
  programs.alacritty = {
	  enable = true;
	  package = pkgs.alacritty;
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
          family = "JetBrainsMonoNerdFontMono";
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
  programs.starship.enable = true;
  targets.genericLinux.enable = true;

  # zsh autcomplete from https://tesar.tech/blog/2024-10-21_nix_os_zsh_autocomplete
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    enableCompletion = true;
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
    initContent = ''
      bindkey "^[[A" up-line-or-search
      bindkey "^[[1;5C" forward-word
      bindkey "^[[1;5D" backward-word
      bindkey  "^[[H"   beginning-of-line
      bindkey  "^[[F"   end-of-line
      bindkey  "^[[3~"  delete-char
      # bindkey -s "^A" "ls^M"

      source ~/.zsh_aliases
      PATH=/home/$USER/.local/bin:$PATH
      source ~/.zshenv.local
    '';
  };

  home.file.".zsh_aliases".source = ./.zsh_aliases;

  programs.git.package = pkgs.gitFull;
  programs.git = {
    enable = true;
    settings.user = {
      name  = "Alex Fernandes Neves";
      email = "alexfneves@gmail.com";
    };
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
        auto-save = {
          focus-lost = true;
          after-delay.enable = true;
          after-delay.timeout = 500;
        };
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
    languages.language = [{
      name = "cpp";
      auto-format = true;
      formatter.command = "clang-format";
    }];
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.btop = {
    enable = true;
    settings = {
      color_theme = "gruvbox_light"; # Options: "Default", "nord", "monokai", "everforest", etc.
      theme_background = false;      # Set to false to let your terminal background show through
    };
  };

  services.ollama = {
    enable = true;
    acceleration = "cuda";
    package = unstablePkgs.ollama-cuda;
  };
  systemd.user.services.ollama.Service.Environment = [
    # "OLLAMA_NUM_PARALLEL=4"
    "OLLAMA_CONTEXT_LENGTH=64000"
  ];
  systemd.user.services.open-webui = {
    Unit = {
      Description = "Open WebUI";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      Environment = [
        "OLLAMA_API_BASE_URL=http://127.0.0.1:11434"
        "DATA_DIR=%h/.local/share/open-webui"
        "WEBUI_AUTH=False"
        # Point the app to the local writable copy
        "FRONTEND_BUILD_DIR=%h/.local/share/open-webui/static"
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

  # Because npm (installed with pkgs.nodejs_20) lives in /nix/store, nothing can be installed globally. We need to change the default npm configuration to install npm packages with -g
  home.sessionVariables = {
    # Use the Nix variable instead of the shell string
    npm_config_prefix = "${config.home.homeDirectory}/.npm-global";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.npm-global/bin"
  ];

  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';
}
