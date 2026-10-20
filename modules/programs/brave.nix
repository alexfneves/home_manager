{ pkgs, hostConfig, inputs, nixGLNvidiaWrap, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;

  # Brave is unfree. On the work host keep the unfree allowance scoped to brave
  # only (a dedicated nixpkgs instance); on the home host just use the shared
  # `pkgs`, which already allows unfree via home.nix / flake.nix.
  pkgsBrave = if hostConfig.useNixGL then
    import inputs.nixpkgs {
      inherit system;
      overlays = [ inputs.nixgl.overlay ];
      config = {
        allowUnfree = true;
        allowUnfreePredicate = pkg: pkg.pname == "brave";
      };
    }
    else pkgs;

  # nixGL is only needed where the GL stack lives outside Nix (Ubuntu work
  # laptop). On NixOS (gmktec) the plain binary already finds its drivers.
  # The wrapper itself now lives in flake.nix (pinned NVIDIA version/sha256 +
  # `nixGLNvidiaWrap`, the Chromium-flag form) so it can be shared with
  # ghostty (modules/editors/ghostty.nix), which uses the flagless form.
  bravePkg = if hostConfig.useNixGL then nixGLNvidiaWrap pkgsBrave.brave else pkgsBrave.brave;

in
{
  # NOTE: `programs.brave` comes from Home Manager's chromium browser module
  # (modules/programs/chromium.nix), so `package` must be a *finished* package:
  # setting `commandLineArgs` here would make the module call `package.override`,
  # which the runCommand nixGL wrapper above does not support. Brave is enabled
  # on every host; only the wrapping is host-conditional.
  programs.brave = {
    enable = true;
    package = bravePkg;
  };
}
