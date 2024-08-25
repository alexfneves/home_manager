{
  description = "Home Manager configuration";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    nixgl.url = "github:guibou/nixGL";
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim/nixos-23.11";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    devenv.url = "github:cachix/devenv/latest";
  };

  outputs = { nixpkgs, home-manager, nixgl, nixvim, self, ... } @ inputs:
    let
      username = "afn";
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system}.extend nixgl.overlay;
      inherit (self) outputs;
    in {
      homeConfigurations."${username}" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./home.nix
          nixvim.homeManagerModules.nixvim
          {
            home.username = "${username}";
            home.homeDirectory = "/home/${username}";
          }
        ];
        extraSpecialArgs = {inherit inputs outputs;};

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
      };
    };
}
