{ pkgs, lib, hostConfig, inputs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;

  # The work laptop has an NVIDIA GPU, so nixGL must wrap the NVIDIA driver
  # libraries, and those must match the kernel module the host runs
  # (/proc/driver/nvidia/version). The version is pinned here so evaluation stays
  # pure. The auto-detect `nixGLDefault` read /proc at eval time through
  # `builtins.currentTime`, which needed `--impure`. When Ubuntu upgrades the
  # driver, update nvidiaVersion and nvidiaSha256 (the SHA256 of NVIDIA's
  # NVIDIA-Linux-x86_64-<version>.run; `nix-prefetch-url <url>` prints it).
  nvidiaVersion = "550.163.01";
  nvidiaSha256 = "0blsmdf9fyw8jjm6fq45bdrldvlj7hnziyz98l0ld5a5ngslk0gg";
  # nixGL's nvidia_x11 must be built with nixGL's own nixpkgs (see the
  # nixgl-nixpkgs input in flake.nix). The NVIDIA driver is unfree, so that
  # instance allows unfree for nvidia packages only.
  nixglPkgs = import inputs.nixgl-nixpkgs {
    inherit system;
    config.allowUnfreePredicate = pkg: lib.hasPrefix "nvidia" (lib.getName pkg);
  };
  nixglLib = import "${inputs.nixgl}/default.nix" {
    pkgs = nixglPkgs;
    enable32bits = true;
    enableIntelX86Extensions = true;
  };
  nixGLBin = nixglLib.nixGLCommon
    (nixglLib.nvidiaPackages { version = nvidiaVersion; sha256 = nvidiaSha256; }).nixGLNvidia;

  nixGLWrap = pkg: pkgs.runCommand "${pkg.name}-nixgl-wrapper" {} ''
    mkdir $out
    ln -s ${pkg}/* $out
    rm $out/bin
    mkdir $out/bin
    for bin in ${pkg}/bin/*; do
      wrapped_bin=$out/bin/$(basename $bin)
      cat > $wrapped_bin <<EOS
#!/usr/bin/env bash
# Run through the pinned NVIDIA nixGL wrapper (see nvidiaVersion above)
exec ${nixGLBin}/bin/nixGL $bin \
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
