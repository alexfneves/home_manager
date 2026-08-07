{
  description = "Home Manager configuration — unified across machines";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixgl.url = "github:guibou/nixGL";
    unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, unstable, home-manager, nixgl, self, ... } @ inputs:
    let
      system = "x86_64-linux";

      pkgs = (import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      }).extend nixgl.overlay;

      unstablePkgs = import unstable {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      };

      # Build a home-manager configuration for a single machine.
      #
      # hostConfig (passed to home.nix) carries everything that differs
      # between machines:
      #   username / email        -> user identity
      #   isNixOS                 -> genericLinux target (Ubuntu etc.)
      #   useNixGL                -> wrap GUI binaries through nixGL (old GPUs/Ubuntu)
      #   enableLlm               -> ROCm stack: ollama, llama-cpp, open-webui
      #   extraPackages           -> extra plain nixpkgs packages for this host
      #   extraUnstablePkgs       -> extra unstable-channel packages for this host
      mkHome = { username, email, isNixOS, useNixGL, enableLlm
               , extraPackages ? [], extraUnstablePkgs ? [] }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            ./home.nix
            {
              home.username = username;
              home.homeDirectory = "/home/${username}";
            }
          ];
          extraSpecialArgs = {
            inherit inputs unstablePkgs;
            hostConfig = {
              inherit username email isNixOS useNixGL enableLlm
                       extraPackages extraUnstablePkgs;
            };
          };
        };
    in {
      homeConfigurations = {
        # --- Home machine: Strix Halo, NixOS (latest) ---
        alexfneves = mkHome {
          username = "alexfneves";
          email = "alexfneves@gmail.com";
          isNixOS = true;
          useNixGL = false;
          enableLlm = true; # ROCm stack: ollama, llama-cpp, open-webui
          extraPackages = with pkgs; [
            steam
            obs-studio
            vlc
            proton-pass
            protonmail-desktop
            proton-vpn
            nvtopPackages.full
          ];
        };

        # --- Work machine: Ubuntu 20, genericLinux, old GPU → needs nixGL ---
        afn = mkHome {
          username = "afn";
          email = "afn@blue-ocean-robotics.com";
          isNixOS = false;
          useNixGL = true; # wrap GUI binaries for the old Ubuntu GL stack
          enableLlm = false; # no ROCm / LLM stack on the work machine
        };
      };
    };
}
