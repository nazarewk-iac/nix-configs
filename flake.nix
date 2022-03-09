{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.nixpkgs-wayland.url = "github:nix-community/nixpkgs-wayland";

  inputs.nixpkgs-update.url = "github:ryantm/nixpkgs-update";

  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.nixos-generators.url = "github:nix-community/nixos-generators";
  inputs.nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

  # inputs.nix-alien.url = "github:thiagokokada/nix-alien";
  # inputs.nix-alien.inputs.nixpkgs.follows = "nixpkgs";
  # inputs.nix-alien.inputs.flake-utils.follows = "flake-utils";
  # inputs.nix-alien.inputs.poetry2nix.follows = "poetry2nix";

  # inputs.nix-ld.url = "github:Mic92/nix-ld";
  # inputs.nix-ld.inputs.nixpkgs.follows = "nixpkgs";
  # inputs.nix-ld.inputs.utils.follows = "flake-utils";

  outputs = {
    nixpkgs,
    nixos-generators,
    ...
 }@flakeInputs : let
    makeSystem = {
      modules ? [],
      system ? "x86_64-linux",
      ...
    }@args: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit flakeInputs system;
      };

      modules = modules ++ [
        ./modules
      ];
    };
  in {
    nixosConfigurations.nazarewk-krul = makeSystem (let system = "x86_64-linux"; in {
      inherit system;
      modules = [
        ./configurations/desktop
        ./machines/krul
        {
          home-manager.users.nazarewk = {
            fresha.development.enable = true;
            fresha.development.bastionUsername = "krzysztof.nazarewski";
          };
        }
      ];
    });

    nixosConfigurations.nazarewk = makeSystem (let system = "x86_64-linux"; in {
      inherit system;
      modules = [
        ./configurations/desktop
        ./machines/dell-latitude-e5470
        {
          home-manager.users.nazarewk = {
            fresha.development.enable = true;
            fresha.development.bastionUsername = "krzysztof.nazarewski";
          };
        }
      ];
    });

    nixosConfigurations.rpi4 = nixpkgs.lib.nixosSystem {
      # nix build '.#nixosConfigurations.rpi4.config.system.build.sdImage' --system aarch64-linux -L
      # see for a next step: https://matrix.to/#/!KqkRjyTEzAGRiZFBYT:nixos.org/$w4Zx8Y0vG0DhlD3zzWReWDaOdRSZvwyrn1tQsLhYDEU?via=nixos.org&via=matrix.org&via=tchncs.de
      system = "aarch64-linux";
      modules = [
        ./rpi4/sd-image.nix
      ];
    };

    packages.x86_64-linux = {
      generators.basic-raw = nixos-generators.nixosGenerate {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        modules = [
          ./modules
          ./configurations/basic
        ];
        format = "raw";
      };
    };
  };
}
