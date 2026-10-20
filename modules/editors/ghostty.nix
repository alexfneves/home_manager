{ lib, pkgs, herdrSessionPackage, hostConfig, nixGLNvidiaWrapWith, ... }:
{
  # Ghostty — the persistent version of what used to be a hand-typed command:
  #
  #   nix run nixpkgs#ghostty -- --theme="Catppuccin Latte"
  #
  # Same theme, but now it comes from the home manager, and it drops into a herdr
  # session on the way in, exactly like alacritty does.
  #
  # The zsh inside that session is NOT configured here and is NOT passed to
  # herdr-session. `herdr-session` takes no command argument at all: any
  # argv[1] is read as one of its internal smoke-test case names and the binary
  # exits 2 (`herdr-session zsh` prints the smoke driver usage). The shell is
  # decided by `default_shell = "zsh"` in herdr/config.toml, which
  # modules/activation.nix symlinks to ~/.config/herdr/config.toml. Chain:
  #
  #   ghostty -> herdr-session (TUI) -> herdr --session <name> -> zsh
  #
  # GL / nixGL: the work notebook (hostConfig.useNixGL = true) keeps its GL
  # stack outside Nix, so it is wrapped through the same pinned-NVIDIA nixGL
  # as brave. On NixOS (gmktec) the plain binary finds its drivers, so
  # `package` stays host-conditional exactly like brave
  # (modules/programs/brave.nix).
  #
  # It uses `nixGLNvidiaWrapWith [ ]` -- the FLAGLESS form -- not the
  # Chromium-flavoured `nixGLNvidiaWrap` brave uses. Those flags
  # (--ozone-platform-hint, --enable-features=..., --disable-gpu-sandbox)
  # are Chromium's, and injecting them breaks ghostty's own subcommands:
  # `ghostty --ozone-platform-hint=auto +validate-config` exits 1 with no
  # message. That is not a corner case -- home-manager runs that very command
  # at activation (xdg.configFile."ghostty/config".onChange, no `|| true`,
  # under set -e), so with the Chromium flags `home-manager switch` on the
  # work host would abort. Without flags it is clean:
  # `nixGL ghostty +validate-config --config-file=...` exits 0.
  #
  # What makes wrapping ghostty possible at all is that the wrapper carries
  # the wrapped package's `meta` through. That matters here specifically
  # because home-manager validates by running
  # `${lib.getExe cfg.package} +validate-config`, and lib.getExe throws at
  # EVAL time on a bare runCommand wrapper with no `meta.mainProgram`. With
  # meta copied over, getExe resolves the wrapper's bin/ghostty -- which is
  # the very binary the wrapper re-execs.
  #
  # The wrapper symlinks the whole original package (`ln -s ${pkg}/* $out`),
  # so `share/` survives and points at real store content. ghostty needs that:
  #   - the systemd user unit ${cfg.package}/share/systemd/user/app-com.mitchellh.ghostty.service
  #   - share/ghostty/themes/* lookups (the "Catppuccin Latte" theme below)
  #   - programs.bat syntax injection (share/bat/syntaxes/*)
  #
  # The one thing the wrapper does NOT carry through is attribute-path access
  # on the package itself — `cfg.package.vim` and friends do not exist on a
  # runCommand wrapper. That is why programs.ghostty.installVimSyntax must stay
  # disabled (its default, false) while the package is wrapped; enabling it would
  # fail with "attribute 'vim' missing".
  programs.ghostty = {
    enable = true;

    package =
      if hostConfig.useNixGL or false
      then nixGLNvidiaWrapWith [ ] pkgs.ghostty
      else pkgs.ghostty;

    settings = {
      # Ghostty resolves themes by their bundled TITLE, strictly: the shipped
      # name is "Catppuccin Latte" (capital C, space between the words).
      # "catppuccin-latte" — the alacritty/herdr spelling, and the example
      # home-manager's own module docs use — fails `ghostty +validate-config`
      # with `theme "catppuccin-latte" not found`.
      theme = "Catppuccin Latte";

      # `command`, not `initial-command`: initial-command covers only the very
      # first surface of a ghostty process, so every later window/tab would
      # open a plain shell instead of the picker. `direct:` skips the
      # `/bin/sh -c` round-trip ghostty otherwise wraps non-direct commands in.
      command = "direct:${herdrSessionPackage}/bin/herdr-session";

      # Alacritty's `window.startup_mode = "Maximized"` equivalent. There is
      # no `window-startup-mode` key in ghostty 1.3.1 — validate-config rejects
      # it as an unknown field.
      maximize = true;

      font-family = "JetBrainsMono Nerd Font Mono";
    };
  };
}
