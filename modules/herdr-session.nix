{ lib, herdrSessionPackage, ... }:
{
  # herdr-session (github:alexfneves/herdr_session) — the replacement for this
  # repo's old herdr-cycle.sh bash script.
  #
  # What it replaces: herdr-cycle listed herdr sessions with fzf and let you
  # create / attach / delete one, destroying the session when it detached. It
  # lived in this repo and reached the terminal through a ~/.local/bin symlink
  # (the now-removed `linkHerdrCycle` activation entry). herdr-session is the
  # same flow as a compiled Odin TUI, shipped by its own flake, installed here
  # as a normal package — so it lands in ~/.nix-profile/bin like everything
  # else and no symlink is needed.
  #
  # The flake exposes no Home Manager module and no overlay, so there is nothing
  # to `imports`; a plain home.packages entry is the integration. The wrapper
  # around it (herdrSessionPackage in flake.nix) puts `herdr` and `ssh` on
  # PATH, which the binary looks up at runtime.
  #
  # Both terminals route through it:
  #   modules/editors/alacritty.nix -> terminal.shell.program
  #   modules/editors/ghostty.nix   -> settings.command
  home.packages = [ herdrSessionPackage ];

  # herdr-session owns ~/.config/herdr_session.json AND REWRITES IT: pressing
  # `t` to switch themes saves the file (a read-modify-write that preserves
  # keys it does not know). Managing this path with home.file / xdg.configFile
  # would point it into the read-only Nix store and make every one of those
  # saves fail with EACCES.
  #
  # So instead of managing it, seed it — only when it does not already exist.
  # A fresh machine gets the settings declared here, and from then on the file
  # belongs to the user and to the app. Same spirit as the config.toml symlink
  # in modules/activation.nix, but copied rather than linked precisely because
  # the app writes. The source is the repo's herdr/herdr_session.json via the
  # store (a literal ~/.config/home-manager path, as the symlink entries use,
  # would make this depend on where the checkout happens to live).
  #
  # Values (see the upstream config.odin for the accepted set):
  #   cleanup_policy = "always"   restores herdr-cycle's destroy-on-detach.
  #                               Upstream's own default used to be "never"
  #                               (sessions accumulate silently); as of the
  #                               02c9ced bump it is "only_created" -- the TUI
  #                               destroys sessions IT created on detach, and
  #                               leaves any others alone. We pin "always"
  #                               explicitly so this host's behaviour does not
  #                               ride along with upstream's default. Other
  #                               valid values: "only_created", "never".
  #                               NB: absent -> "only_created", but an
  #                               unrecognised value -> "never" (config.odin
  #                               sets CLEANUP_LABEL_NONE on a bad value), so
  #                               this key must be spelled exactly.
  #   theme is deliberately NOT set here. The app's own default plus the
  #   user's runtime theme switching (pressing `t`, which writes this very
  #   file) decide it -- home-manager seeding a theme would only be a first-run
  #   guess that the user then overrides anyway. Upstream's default is
  #   gruvbox-dark, so the TUI is dark even against latte terminals; that is
  #   the intended split of responsibility, not an oversight.
  #
  # IMPORTANT -- this seed only fires on a file that does not exist. It will NOT
  # update an existing ~/.config/herdr_session.json, so on any machine already
  # carrying one, the effective cleanup policy is whatever that file plus the
  # upstream default say, NOT what this module declares. On this box the live
  # file predates cleanup_policy entirely, so `nix flake lock --update-input
  # herdr-session` moved it from "never" to "only_created" without a reseed.
  # Set it by hand (or delete the file and let the seed run) if that is not
  # wanted.
  home.activation.herdrSessionConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config"
    if [ ! -e "$HOME/.config/herdr_session.json" ]; then
      cp ${../herdr/herdr_session.json} "$HOME/.config/herdr_session.json"
    fi
  '';
}
