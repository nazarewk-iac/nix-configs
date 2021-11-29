{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.wayland.url = "github:nix-community/nixpkgs-wayland";
#  inputs.keepass.url = "github:nazarewk/nixpkgs/keepass-keetraytotp";
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.poetry2nix.url = "github:nix-community/poetry2nix";
  inputs.poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.poetry2nix.inputs.flake-utils.follows = "flake-utils";

  inputs.nix-alien.url = "github:thiagokokada/nix-alien";
  inputs.nix-alien.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-alien.inputs.flake-utils.follows = "flake-utils";
  inputs.nix-alien.inputs.poetry2nix.follows = "poetry2nix";

  inputs.nix-ld.url = "github:Mic92/nix-ld";
  inputs.nix-ld.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-ld.inputs.utils.follows = "flake-utils";

  outputs = inputs:
    let system = "x86_64-linux";
    in {
      nixosConfigurations.nazarewk = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
            nix.binaryCachePublicKeys = [
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
              "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
            nix.binaryCaches = [
              "https://cache.nixos.org"
              "https://nixpkgs-wayland.cachix.org"
              "https://nix-community.cachix.org"
            ];
            nixpkgs.overlays = [
              inputs.wayland.overlay
#              (self: super: {
#                keepass-keetraytotp =
#                  inputs.keepass.legacyPackages.${system}.keepass-keetraytotp;
#                keepass-charactercopy =
#                  inputs.keepass.legacyPackages.${system}.keepass-charactercopy;
#                keepass-qrcodeview =
#                  inputs.keepass.legacyPackages.${system}.keepass-qrcodeview;
#              })
            ];
          }
          ./legacy/nixos/configuration.nix

          {
            environment.systemPackages = [
              inputs.nixpkgs.legacyPackages.${system}.nix-index
              inputs.nix-alien.packages.${system}.nix-alien
              inputs.nix-alien.packages.${system}.nix-index-update
            ];
          }

          {
            programs.gnupg.package =
              inputs.nixpkgs.legacyPackages.${system}.gnupg.overrideAttrs
              (old: rec {
                pname = "gnupg";
                # version = "2.2.33";
                version = "2.2.28";

                src = inputs.nixpkgs.legacyPackages.${system}.fetchurl {
                  url = "mirror://gnupg/gnupg/${pname}-${version}.tar.bz2";
                  # sha256 = "8688836e8c043d70410bb64d72de6ae15176e09ecede8d24528b4380c000e4e3";
                  sha256 =
                    "sha256-b/iR/HWDqcP7nwl+4NHeChJGnUtTmX57pQZJUGN9+uw=";
                };
              });
          }

          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.nazarewk = import ./legacy/hm/home.nix;
          }
        ];
      };
    };
}
