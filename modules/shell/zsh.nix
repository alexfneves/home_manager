{ pkgs, ... }:
{
  # zsh autcomplete from https://tesar.tech/blog/2024-10-21_nix_os_zsh_autocomplete
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    enableCompletion = false; # maybe this is necessary for the plugin to work
    syntaxHighlighting.enable = true;
    completionInit = "autoload -U compinit && compinit -u";
    shellAliases = {
      j = "cd $(fd -H -I -t d . ~ | fzf)";
      e = "j && hx";
      g = "lazygit";
      gl = "git log --graph --decorate --pretty=oneline --abbrev-commit --all";
      gk = "gitk --all";
      gg = "git gui";
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

    plugins = [
      {
        name = "zsh-autocomplete";
        src = pkgs.fetchFromGitHub {
          owner = "marlonrichert";
          repo = "zsh-autocomplete";
          rev = "25.03.19";
          sha256 = "sha256-/6V6IHwB5p0GT1u5SAiUa20LjFDSrMo731jFBq/bnpw=";
        };
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

  home.file.".zsh_aliases".source = ../../.zsh_aliases;
}
