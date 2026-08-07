{ config, ... }:
{
  # Because npm (installed with pkgs.nodejs_20) lives in /nix/store, nothing can be installed globally. We need to change the default npm configuration to install npm packages with -g
  home.sessionVariables = {
    # Use the Nix variable instead of the shell string
    npm_config_prefix = "${config.home.homeDirectory}/.npm-global";
    EDITOR = "hx";
    VISUAL = "hx";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.npm-global/bin"
  ];

  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';
}
