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
  # Run the nws workspace daemon (modules/nws.nix).
  enableNws = true;
  extraPackages = with pkgs; [
    drawio
    claude-code
  ];
}
