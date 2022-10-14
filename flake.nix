{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixpkgs-wayland.url = "github:nix-community/nixpkgs-wayland";
    nixpkgs-gpg236.url = "github:nixos/nixpkgs/22e81f39ace64964bae3b6c89662d1221a11324c";
    lib-aggregate = { url = "github:nix-community/lib-aggregate"; };

    nixpkgs-update.url = "github:ryantm/nixpkgs-update";
    home-manager.url = "github:nix-community/home-manager";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-generators.url = "github:nix-community/nixos-generators";
    # nix-alien.url = "github:thiagokokada/nix-alien";
    # nix-ld.url = "github:Mic92/nix-ld";
  };

  outputs =
    { self
    , flake-utils
    , nixpkgs
    , nixos-generators
    , home-manager
    , ...
    }@inputs:
    let
      inherit (inputs.lib-aggregate) lib;
      inherit (inputs) self;
    in
    (flake-utils.lib.eachDefaultSystem
      (system:
      let
        # adapted from https://github.com/nix-community/nixpkgs-wayland/blob/b703de94dd7c3d73a03b5d30b248b8984ad8adb7/flake.nix#L119-L127
        pkgsFor = pkgs: overlays:
          import pkgs {
            inherit system overlays;
            config.allowUnfree = true;
            config.allowAliases = false;
          };
        pkgs_ = lib.genAttrs (builtins.attrNames inputs) (inp: pkgsFor inputs."${inp}" [ ]);
        opkgs_ = overlays: lib.genAttrs (builtins.attrNames inputs) (inp: pkgsFor inputs."${inp}" overlays);
        kdnpkgs = (opkgs_ [ self.overlays.default ]).nixpkgs;
      in
      {
        apps = { };
        checks = { };
        devShells = { };
        packages = kdnpkgs;
        homeConfigurations = {
          nazarewk = home-manager.lib.homeManagerConfiguration {
            pkgs = kdnpkgs;
            modules = [
              ./users/nazarewk/home.nix
            ];
          };
        };
      }))
    // (
      let
        makeSystem =
          { modules ? [ ]
          , system ? "x86_64-linux"
          , ...
          }: nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = {
              inherit inputs system;
              waylandPkgs = inputs.nixpkgs-wayland.packages.${system};
            };

            modules = [
              self.nixosModules.default
              { nixpkgs.overlays = [ self.overlays.default ]; }
            ] ++ modules;
          };
      in
      {
        overlays.default = final: prev: { kdn = import ./packages { pkgs = prev; }; };
        nixosModules.default = ./modules;

        nixosConfigurations.nazarewk-krul = makeSystem (
          let system = "x86_64-linux"; in
          {
            inherit system;
            modules = [
              ./configurations/desktop
              ./machines/krul
              {
                home-manager.users.nazarewk = { };
              }
            ];
          }
        );

        nixosConfigurations.nazarewk = makeSystem (
          let system = "x86_64-linux"; in
          {
            inherit system;
            modules = [
              ./configurations/desktop
              ./machines/dell-latitude-e5470
              {
                home-manager.users.nazarewk = { };
              }
            ];
          }
        );

        nixosConfigurations.wg-0 = makeSystem (
          let system = "x86_64-linux"; in
          {
            inherit system;
            modules = [
              ./configurations/headless
              ./machines/hetzner/wg-0
            ];
          }
        );

        nixosConfigurations.rpi4 = nixpkgs.lib.nixosSystem {
          # nix build '.#nixosConfigurations.rpi4.config.system.build.sdImage' --system aarch64-linux -L
          # see for a next step: https://matrix.to/#/!KqkRjyTEzAGRiZFBYT:nixos.org/$w4Zx8Y0vG0DhlD3zzWReWDaOdRSZvwyrn1tQsLhYDEU?via=nixos.org&via=matrix.org&via=tchncs.de
          system = "aarch64-linux";
          modules = [
            ./rpi4/sd-image.nix
          ];
        };
      }
    );
}
