{ config, lib, hostConfig, ... }:
{
  # Because npm (installed with pkgs.nodejs_20) lives in /nix/store, nothing can be installed globally. We need to change the default npm configuration to install npm packages with -g
  home.sessionVariables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };

  # Nodejs / npm global setup – only enabled per host
} // lib.mkIf (hostConfig.enableNodejs or false) {
  home.sessionVariables.npm_config_prefix = "${config.home.homeDirectory}/.npm-global";

  home.sessionPath = [
    "${config.home.homeDirectory}/.npm-global/bin"
  ];

  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';
}
