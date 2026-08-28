{ pkgs, lib, hostConfig, inputs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
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

  # Isolate unfree allowance to brave on work-notebook host
  pkgsBrave = if hostConfig.useNixGL && hostConfig.hostname == "afn" then
    import inputs.nixpkgs {
      inherit system;
      overlays = [ inputs.nixgl.overlay ];
      config = {
        allowUnfree = true;
        allowUnfreePredicate = pkg: pkg.pname == "brave";
      };
    }
    else pkgs;

  bravePkg = if hostConfig.useNixGL then nixGLWrap pkgsBrave.brave else pkgsBrave.brave;

in
{
  programs.brave = lib.mkIf (hostConfig.useNixGL && hostConfig.hostname == "afn") {
    enable = true;
    package = bravePkg;
  };
}
