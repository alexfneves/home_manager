{ pkgs }:
{
  hostname = "afn";
  username = "afn";
  email = "afn@blue-ocean-robotics.com";
  isNixOS = false;
  useNixGL = true;
  enableLlm = false;
  enableNodejs = false;
  enableCleanNixEnv = true;
  extraPackages = with pkgs; [
    drawio
  ];
}
