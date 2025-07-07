{
  description = "Home Manager configuration";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixgl.url = "github:guibou/nixGL";
    unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    devenv.url = "github:cachix/devenv/latest";
  };

  outputs = { nixpkgs, unstable, home-manager, nixgl, self, ... } @ inputs:
    let
      username = "alexfneves";
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system}.extend nixgl.overlay;
      unstablePkgs = import unstable {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      };
      inherit (self) outputs;
    in {
      homeConfigurations."${username}" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./home.nix
          {
            home.username = "${username}";
            home.homeDirectory = "/home/${username}";
          }
        ];
        extraSpecialArgs = {
          inherit inputs outputs;
          unstablePkgs = unstablePkgs;
        };

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
      };
    };
}
