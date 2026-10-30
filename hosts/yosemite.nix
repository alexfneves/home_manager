{ pkgs }:
{
  # yosemite — NixOS box on the LAN (deployed with colmena from
  # ~/gits/yosemite). afn's home here is *this* home-manager config, so the
  # environment matches the work notebook.
  #
  # NOTE: this repo is PUBLIC. Keep credentials out of these host files.
  hostname = "yosemite";
  username = "afn";
  email = "afn@blue-ocean-robotics.com";

  # NixOS host: home.nix sets `targets.genericLinux.enable = !isNixOS`, so
  # this must be true or the Ubuntu target gets applied here.
  isNixOS = true;

  # NixOS configures the display/GPU stack itself; nixGL is only for the
  # non-NixOS hosts.
  useNixGL = false;

  # Same as the work notebook: no local LLM stack on this box.
  enableLlm = false;
  enableNodejs = false;

  # modules/clean-nix-for-ubuntu.nix is Ubuntu-specific - off on NixOS.
  enableCleanNixEnv = false;

  # nws runs on yosemite from the NixOS config (nixosModules.default in
  # ~/gits/yosemite), for every user. Keep this off here, or afn would run two
  # daemons that both want the default control port.
  enableNws = false;

  extraPackages = with pkgs; [
    drawio
    claude-code
  ];
}
