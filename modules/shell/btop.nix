{ ... }:
{
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "gruvbox_light"; # Options: "Default", "nord", "monokai", "everforest", etc.
      theme_background = false;      # Set to false to let your terminal background show through
    };
  };
}
