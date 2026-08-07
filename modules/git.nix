{ pkgs, hostConfig, ... }:
{
  programs.git.package = pkgs.gitFull;
  programs.git = {
    enable = true;
    settings.user = {
      name  = "Alex Fernandes Neves";
      email = hostConfig.email;
    };
  };
}
