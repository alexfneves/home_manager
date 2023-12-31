{ config, pkgs, lib, ... }:
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
  home.username = "alexfneves";
  home.homeDirectory = "/home/alexfneves";

  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    exa
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
    lazygit
    exa
    lf
    clang
    clang-tools
    lldb
    sshfs
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "23.05";

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
      shell = {
        program = "zsh";
        args = ["-l" "-c" "zellij"];
      };
      font = {
        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Medium";
        };
      };
    };
  };
  programs.starship.enable = true;
  targets.genericLinux.enable = true;

  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    enableCompletion = false;
    shellAliases = {
      j = "cd $(fd -H -t d . ~ | fzf)";
      e = "j && nvim";
      gl = "git log --graph --decorate --pretty=oneline --abbrev-commit --all";
      g = "lazygit";
      za = "alacritty --command \"zellij a $(zellij list-sessions | fzf)\"";
      u = "home-manager switch";
    };
    initExtra = ''
      bindkey "''${key[Up]}" up-line-or-search
      bindkey "^[[1;5C" forward-word
      bindkey "^[[1;5D" backward-word
      # bindkey -s "^A" "ls^M"
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
        name = "zsh-autocomplete";
        file = "zsh-autocomplete.plugin.zsh";
        src = "${pkgs.zsh-autocomplete}/share/zsh-autocomplete";
      }     
    ];
  };

  programs.zellij = {
    enable = true;
  };
  xdg.configFile."zellij".source = ./zellij;

  programs.helix = {
    enable = true;
    package = pkgs.helix;
    settings = {
      theme = "onedark";
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
      # keys.normal = {
      #   space.space = "file_picker";
      #   space.w = ":w";
      #   space.q = ":q";
      #   esc = [ "collapse_selection" "keep_primary_selection" ];
      # };
    };
  };

}
