{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixpkgs-wayland.url = "github:nix-community/nixpkgs-wayland";
    nixpkgs-gpg236.url = "github:nixos/nixpkgs/22e81f39ace64964bae3b6c89662d1221a11324c";
    lib-aggregate = { url = "github:nix-community/lib-aggregate"; };

    nixpkgs-update.url = "github:ryantm/nixpkgs-update";
    home-manager.url = "github:nix-community/home-manager";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # nix-alien.url = "github:thiagokokada/nix-alien";
    # nix-ld.url = "github:Mic92/nix-ld";
  };

  outputs =
    inputs:
    let
      inherit (inputs.lib-aggregate) lib;
      inherit (inputs) self flake-parts nixpkgs home-manager;
      args = {
        inherit self;
        specialArgs = { };
      };
    in
    flake-parts.lib.mkFlake args {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      perSystem = { config, self', inputs', pkgs, system, ... }:
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
          packages.default = kdnpkgs;
        };
      flake = {
        overlays.default = final: prev: (
          let
            pkgs = prev;
            lib = pkgs.lib;
          in
          # automatically discover all packages with names of packages being names of their folders
          lib.pipe ./packages [
            lib.filesystem.listFilesRecursive
            # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
            (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
            (map (path: {
              name =
                let pieces = lib.splitString "/" (toString path); len = builtins.length pieces;
                in builtins.elemAt pieces (len - 2);
              value = pkgs.callPackage path { };
            }))
            builtins.listToAttrs
            (packages: { kdn = packages; }) # namespace packages to kdn
          ]
        );
        nixosModules.default = ./modules;

        nixosConfigurations =
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
            nazarewk-krul = makeSystem {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.krul.enable = true; }];
            };

            nazarewk = makeSystem {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.dell-latitude-e5470.enable = true; }];
            };

            wg-0 = makeSystem {
              system = "x86_64-linux";
              modules = [ ./machines/hetzner/wg-0 ];
            };

            rpi4 = nixpkgs.lib.nixosSystem {
              # nix build '.#rpi4.config.system.build.sdImage' --system aarch64-linux -L
              # see for a next step: https://matrix.to/#/!KqkRjyTEzAGRiZFBYT:nixos.org/$w4Zx8Y0vG0DhlD3zzWReWDaOdRSZvwyrn1tQsLhYDEU?via=nixos.org&via=matrix.org&via=tchncs.de
              system = "aarch64-linux";
              modules = [ ./rpi4/sd-image.nix ];
            };
          };
      };
    };
}
