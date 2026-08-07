{ lib, ... }:
{
  # Keep herdr's config.toml in this git repo, but expose it to herdr at
  # ~/.config/herdr/config.toml via a real symlink. We deliberately DON'T use
  # home.file / xdg.configFile here: those copy the file into the read-only nix
  # store, which would stop herdr (and us) from editing it.
  home.activation.linkHerdrConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/herdr"
    ln -sfn "$HOME/.config/home-manager/herdr/config.toml" "$HOME/.config/herdr/config.toml"
  '';
}
