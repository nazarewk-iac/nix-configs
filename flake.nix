{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.wayland.url = "github:nix-community/nixpkgs-wayland";
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

  outputs = {
    nixpkgs,
    wayland,
    home-manager,
    flake-utils,
    poetry2nix,
    nix-alien,
    nix-ld,
    ...
 } : {
      nixosConfigurations.rpi4 = nixpkgs.lib.nixosSystem {
        # nix build '.#nixosConfigurations.rpi4.config.system.build.sdImage' --system aarch64-linux -L
        # see for a next step: https://matrix.to/#/!KqkRjyTEzAGRiZFBYT:nixos.org/$w4Zx8Y0vG0DhlD3zzWReWDaOdRSZvwyrn1tQsLhYDEU?via=nixos.org&via=matrix.org&via=tchncs.de
        system = "aarch64-linux";
        modules = [
          ./rpi4/sd-image.nix
        ];
      };
      nixosConfigurations.nazarewk = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/sway-systemd
          ./modules/aws-vault
          ./modules/nix-direnv
          ./modules/development/python
          ./modules/development/cloud
          ./modules/packaging/asdf
          ./modules/hardware/yubikey
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
              wayland.overlay
              (self: super: {
              })
            ];
            programs.aws-vault.enable = true;
            programs.nix-direnv.enable = true;
            services.sway-systemd.enable = true;
          }
          ./legacy/nixos/configuration.nix
          ./legacy/nixos/podman.nix

          {
            environment.systemPackages = [
              nixpkgs.legacyPackages.x86_64-linux.nix-index
              nix-alien.packages.x86_64-linux.nix-alien
              nix-alien.packages.x86_64-linux.nix-index-update
            ];
          }

          {
            programs.gnupg.package =
              nixpkgs.legacyPackages.x86_64-linux.gnupg.overrideAttrs
              (old: rec {
                pname = "gnupg";
                # version = "2.2.33";
                version = "2.2.28";

                src = nixpkgs.legacyPackages.x86_64-linux.fetchurl {
                  url = "mirror://gnupg/gnupg/${pname}-${version}.tar.bz2";
                  # sha256 = "8688836e8c043d70410bb64d72de6ae15176e09ecede8d24528b4380c000e4e3";
                  sha256 =
                    "sha256-b/iR/HWDqcP7nwl+4NHeChJGnUtTmX57pQZJUGN9+uw=";
                };
              });
          }

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }
        ];
      };
    };
}
