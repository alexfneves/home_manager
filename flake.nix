{
  description = "Home Manager configuration — unified across machines";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixgl.url = "github:guibou/nixGL";
    unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Latest RELEASE of ollama, so we can build ollama-rocm straight from
    # GitHub instead of waiting for nixpkgs-unstable to catch up.
    # Pinned to a release tag — main has no real version string (it reports
    # "0.0.0"), which the ollama registry rejects when pulling models. Bump to
    # a newer tag with: nix flake lock --update-input ollama-git
    ollama-git = {
      url = "github:ollama/ollama/v0.32.9";
      flake = false;
    };
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

      # ---- ollama-rocm built from the latest ollama GitHub release ----
      # The whole derivation lives in ./ollama-rocm-git.nix so flake.nix stays
      # clean; the `ollama-git` input above is the source it builds from.
      ollamaRocmGit = import ./ollama-rocm-git.nix {
        inherit pkgs unstablePkgs;
        lib = pkgs.lib;
        ollamaGit = inputs.ollama-git;
      };

    # Build a home-manager configuration for a single machine.
      #
      # hostConfig (passed to home.nix) carries everything that differs
      # between machines:
      #   username / email        -> user identity
      #   isNixOS                 -> genericLinux target (Ubuntu etc.)
      #   useNixGL                -> wrap GUI binaries through nixGL (old GPUs/Ubuntu)
      #   enableLlm               -> ROCm stack: ollama, llama-cpp, open-webui
      #   enableNodejs            -> nodejs + npm global setup
      #   ollamaSource            -> which ollama-rocm to use: "nixpkgs" (default) or "git"
      #   extraPackages           -> extra plain nixpkgs packages for this host
      #   extraUnstablePkgs       -> extra unstable-channel packages for this host
      mkHome = { username, hostname, email, isNixOS, useNixGL, enableLlm, enableNodejs ? false
               , ollamaSource ? "nixpkgs"
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
            inherit inputs unstablePkgs ollamaRocmGit;
            hostConfig = {
              inherit username hostname email isNixOS useNixGL enableLlm enableNodejs ollamaSource
                       extraPackages extraUnstablePkgs;
            };
          };
        };
    in let
      hosts = {
        gmktec = import ./hosts/gmktec.nix { inherit pkgs; };
        work-notebook = import ./hosts/work-notebook.nix { inherit pkgs; };
      };
    in {
      # Directly buildable/testable: `nix build .#ollama-rocm-git`
      packages.${system} = {
        ollama-rocm = unstablePkgs.ollama-rocm;
        ollama-rocm-git = ollamaRocmGit;
      };
      homeConfigurations = {
        "${hosts.gmktec.username}@${hosts.gmktec.hostname}" = mkHome hosts.gmktec;
        "${hosts.work-notebook.username}@${hosts.work-notebook.hostname}" = mkHome hosts.work-notebook;
      };
    };
}
