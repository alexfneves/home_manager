{ pkgs, ... }:
{
  programs.helix = {
    enable = true;
    defaultEditor = true;
    package = pkgs.helix;
    settings = {
      theme = "catppuccin_latte";
      editor = {
        line-number = "relative";
        auto-save = {
          focus-lost = true;
          after-delay.enable = true;
          after-delay.timeout = 500;
        };
        bufferline = "multiple";
        color-modes = true;
      };
      editor.cursor-shape = {
        insert = "bar";
        normal = "block";
        select = "underline";
      };
      editor.file-picker.hidden = false;
      editor.whitespace.render.tab = "all";
      editor.indent-guides.render = true;
      editor.soft-wrap.enable = true;
      editor.default-yank-register = "+";
      keys.normal = {
      #   space.space = "file_picker";
      #   space.w = ":w";
      #   space.q = ":q";
        esc = [ "collapse_selection" "keep_primary_selection" ];
        "tab" = ":bn";
        "S-tab" = ":bp";
        "d" = "delete_selection_noyank";
        "c" = "change_selection_noyank";
        "A-d" = "delete_selection";
        "A-c" = "change_selection";
      };
    };
    languages.language = [{
      name = "cpp";
      auto-format = true;
      formatter.command = "clang-format";
    }];
  };
}
