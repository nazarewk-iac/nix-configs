{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-lib.url = "github:NixOS/nixpkgs/nixos-unstable?dir=lib";
    nixpkgs-gpg236.url = "github:nixos/nixpkgs/22e81f39ace64964bae3b6c89662d1221a11324c";

    nixpkgs-wayland = {
      url = "github:nix-community/nixpkgs-wayland";
      inputs.flake-compat.follows = "flake-compat";
      inputs.lib-aggregate.follows = "lib-aggregate";
      inputs.nix-eval-jobs.follows = "nix-eval-jobs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lib-aggregate = {
      url = "github:nix-community/lib-aggregate";
      inputs.nixpkgs-lib.follows = "nixpkgs-lib";
      inputs.flake-utils.follows = "flake-utils";
    };
    nix-eval-jobs = {
      url = "github:nix-community/nix-eval-jobs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    #nixpkgs-update = {
    #  url = "github:ryantm/nixpkgs-update";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #  inputs.flake-compat.follows = "flake-compat";
    #};
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs-lib";
    };
    # nix-alien.url = "github:thiagokokada/nix-alien";
    # nix-ld.url = "github:Mic92/nix-ld";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };
    poetry2nix = {
      #url = "github:nazarewk/poetry2nix";
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    microvm = {
      url = "github:nazarewk/microvm.nix/side-effect-free-imports";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixlib.follows = "nixpkgs-lib";
    };

    disko = {
      # url = "github:nix-community/disko";
      # https://github.com/nix-community/disko/pull/111
      url = "github:nazarewk/disko/c97c52d6f5d06ab8839b5f73e3d60c123770e052";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      inherit (inputs) self flake-parts home-manager nixpkgs poetry2nix disko;
      lib = import ./lib { inherit (inputs.nixpkgs) lib; };
      flakeLib = lib.kdn.flakes.forFlake self;
      args = {
        inherit inputs;
        specialArgs = { };
      };
    in
    (flake-parts.lib.mkFlake args {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      perSystem = { config, self', inputs', system, ... }:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          # inspired by https://github.com/NixOS/nix/issues/3803#issuecomment-748612294
          # usage: nix run '.#repl'
          apps.repl = {
            type = "app";
            program = "${pkgs.writeShellScriptBin "repl" ''
            confnix=$(mktemp)
            trap "rm '$confnix' || true" EXIT
            echo "builtins.getFlake (toString "$PWD")" >$confnix
            nix repl "$confnix"
          ''}/bin/repl";
          };
          checks = { };
          devShells = { };
          packages = lib.mkMerge [
            (lib.filterAttrs (n: pkg: lib.isDerivation pkg) (flakeLib.overlayedInputs { inherit system; }).nixpkgs.kdn)
            (flakeLib.microvm.packages system)
          ];
        };
      flake = {
        inherit lib;

        overlays.default = lib.composeManyExtensions [
          poetry2nix.overlay
          (final: prev: (import ./packages { inherit inputs self; pkgs = prev; }))
          (final: prev: {
            # work around not using flake-utils which sets it up on `pkgs.system`
            # see https://github.com/numtide/flake-utils/blob/1ed9fb1935d260de5fe1c2f7ee0ebaae17ed2fa1/check-utils.nix#L4
            system = final.stdenv.system;
            lib = import ./lib { inherit (prev) lib; };
          })
        ];
        nixosModules.default = ./modules;

        nixosConfigurations = lib.mkMerge [
          {
            oams = flakeLib.nixos.system {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.oams.enable = true; }
                {
                  networking.hostId = "ce0f2f33"; # cut -c-8 </proc/sys/kernel/random/uuid
                  networking.hostName = "oams";
                }];
            };

            nazarewk-krul = flakeLib.nixos.system {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.krul.enable = true; }
                {
                  networking.hostId = "81d86976"; # cut -c-8 </proc/sys/kernel/random/uuid
                  networking.hostName = "nazarewk-krul";
                }];
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
