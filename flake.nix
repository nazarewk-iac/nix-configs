{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    microvm.url = "github:nazarewk/microvm.nix/side-effect-free-imports";
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
      flakeLib = lib.kdn.flakes.forFlake self;
      args = {
        inherit self;
        specialArgs = { };
      };
    in
    (flake-parts.lib.mkFlake args {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        apps = {
          # see https://github.com/NixOS/nix/issues/3803#issuecomment-748612294
          # usage: nix run '.#repl'
          repl = {
            type = "app";
            program = "${pkgs.writeShellScriptBin "repl" ''
                confnix=$(mktemp)
                trap "rm $confnix || true" EXIT
                echo "builtins.getFlake (toString ./.)" >$confnix
                nix repl $confnix
              ''}/bin/repl";
          };
        };
        checks = { };
        devShells = { };
        packages = lib.mkMerge [
          (lib.filterAttrs (n: pkg: lib.isDerivation pkg) (flakeLib.packagesForOverlay { inherit system; }).kdn)
          (flakeLib.microvm.packages system)
        ];
      };
      flake = {
        inherit lib;

        overlays.default = final: prev: (import ./packages { pkgs = prev; }) // {
          # work around not using flake-utils which sets it up on `pkgs.system`
          # see https://github.com/numtide/flake-utils/blob/1ed9fb1935d260de5fe1c2f7ee0ebaae17ed2fa1/check-utils.nix#L4
          system = final.stdenv.system;
        };
        nixosModules.default = ./modules;

        nixosConfigurations = lib.mkMerge [
          {
            oams = flakeLib.nixos.system {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.oams.enable = true; }];
            };

            nazarewk-krul = flakeLib.nixos.system {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.krul.enable = true; }];
            };

            nazarewk = flakeLib.nixos.system {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.dell-latitude-e5470.enable = true; }];
            };

            wg-0 = flakeLib.nixos.system {
              system = "x86_64-linux";
              modules = [ ./machines/hetzner/wg-0 ];
            };

            #rpi4 = lib.nixosSystem {
            #  # nix build '.#rpi4.config.system.build.sdImage' --system aarch64-linux -L
            #  # see for a next step: https://matrix.to/#/!KqkRjyTEzAGRiZFBYT:nixos.org/$w4Zx8Y0vG0DhlD3zzWReWDaOdRSZvwyrn1tQsLhYDEU?via=nixos.org&via=matrix.org&via=tchncs.de
            #  system = "aarch64-linux";
            #  modules = [ ./rpi4/sd-image.nix ];
            #};
          }
          (flakeLib.microvm.configuration {
            name = "hello-microvm";
            modules = [{
              system.stateVersion = "22.11";
              kdn.profile.machine.baseline.enable = true;
            }];
          })
        ];
      };
    });
}
