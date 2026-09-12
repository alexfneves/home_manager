{ pkgs, lib, hostConfig, inputs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;

  # WARNING: `nixgl.packages.<system>.nixGLDefault` is the *auto-detect* variant.
  # It reads /proc/driver/nvidia/version at eval time via `builtins.currentTime` +
  # `builtins.readFile`, so evaluating it needs `--impure` (a pure eval fails with
  # "attribute 'currentTime' missing"). If the work laptop ever gives trouble,
  # switch to a pure variant instead, e.g. `pkgs.nixgl.nixGLIntel` (Mesa, what
  # modules/editors/alacritty.nix uses) or a pinned `nixgl.nvidiaPackages`.
  nixGLWrap = pkg: pkgs.runCommand "${pkg.name}-nixgl-wrapper" {} ''
    mkdir $out
    ln -s ${pkg}/* $out
    rm $out/bin
    mkdir $out/bin
    for bin in ${pkg}/bin/*; do
      wrapped_bin=$out/bin/$(basename $bin)
      cat > $wrapped_bin <<EOS
#!/usr/bin/env bash
# Pull nixGLDefault directly from the flake packages (no .auto needed here)
exec ${inputs.nixgl.packages.${system}.nixGLDefault}/bin/nixGL $bin \
  --ozone-platform-hint=auto \
  --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,Vulkan \
  --disable-gpu-sandbox \
  "\$@"
EOS
      chmod +x $wrapped_bin
    done
  '';

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
  bravePkg = if hostConfig.useNixGL then nixGLWrap pkgsBrave.brave else pkgsBrave.brave;

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
