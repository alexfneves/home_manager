{ hostConfig, inputs, ... }:

# nws: the Nix Workspace root manager daemon. The package and its Home Manager
# module live in their own repo (github:alexfneves/nws), pinned as the `nws`
# input in flake.nix; importing the module is all that is needed here.
#
# It runs `nws service` as a systemd user unit and keeps its state under
# ~/.config/nws. Enabled per host with hostConfig.enableNws (see hosts/*.nix).
{
  imports = [ inputs.nws.homeManagerModules.default ];

  services.nws.enable = hostConfig.enableNws or false;
}
