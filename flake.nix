{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";

    nixpkgs-wayland.url = "github:nix-community/nixpkgs-wayland";
    nixpkgs-gpg236.url = "github:nixos/nixpkgs/22e81f39ace64964bae3b6c89662d1221a11324c";

    nixpkgs-update.url = "github:ryantm/nixpkgs-update";
    home-manager.url = "github:nix-community/home-manager";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # nix-alien.url = "github:thiagokokada/nix-alien";
    # nix-ld.url = "github:Mic92/nix-ld";
  };

  outputs =
    inputs:
    let
      inherit (inputs) self flake-parts home-manager;
      lib = import ./lib { inherit (inputs.nixpkgs) lib; };
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
          apps = {
            # see https://github.com/NixOS/nix/issues/3803#issuecomment-748612294
            # usage: nix run '.#repl'
            repl = {
              type = "app";
              program = "${pkgs.writeShellScriptBin "repl" ''
                confnix=$(mktemp)
                echo "builtins.getFlake (toString $(git rev-parse --show-toplevel))" >$confnix
                trap "rm $confnix" EXIT
                nix repl $confnix
              ''}/bin/repl";
            };
          };
          checks = { };
          devShells = { };
          packages = lib.filterAttrs (n: pkg: lib.isDerivation pkg) kdnpkgs.kdn;
        };
      flake = {
        inherit lib;

        overlays.default = final: prev: import ./packages { pkgs = prev; };
        nixosModules.default = ./modules;

        nixosConfigurations =
          let
            nixosSystem = lib.kdn.flakes.nixosSystem self;
          in
          {
            nazarewk-krul = nixosSystem {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.krul.enable = true; }];
            };

            nazarewk = nixosSystem {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.dell-latitude-e5470.enable = true; }];
            };

            wg-0 = nixosSystem {
              system = "x86_64-linux";
              modules = [ ./machines/hetzner/wg-0 ];
            };

            rpi4 = lib.nixosSystem {
              # nix build '.#rpi4.config.system.build.sdImage' --system aarch64-linux -L
              # see for a next step: https://matrix.to/#/!KqkRjyTEzAGRiZFBYT:nixos.org/$w4Zx8Y0vG0DhlD3zzWReWDaOdRSZvwyrn1tQsLhYDEU?via=nixos.org&via=matrix.org&via=tchncs.de
              system = "aarch64-linux";
              modules = [ ./rpi4/sd-image.nix ];
            };
          };
      };
    };
}
