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

  # Same approach for spotatui's settings: keep config.yml in this git repo but
  # expose it at ~/.config/spotatui/config.yml via a real symlink so both we and
  # spotatui can edit it. client.yml (auth credentials) is deliberately left out.
  home.activation.linkSpotatuiConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/spotatui"
    ln -sfn "$HOME/.config/home-manager/spotatui/config.yml" "$HOME/.config/spotatui/config.yml"
  '';
}
