{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-lib.url = "github:NixOS/nixpkgs/nixos-unstable?dir=lib";

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
      inputs.flake-parts.follows = "flake-parts";
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
    };
    poetry2nix = {
      #url = "github:nazarewk/poetry2nix";
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixlib.follows = "nixpkgs-lib";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-images = {
      url = "github:nix-community/nixos-images";
      inputs.nixos-unstable.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixinate = {
      url = "github:matthewcroughan/nixinate";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    devenv = {
      #url = "github:cachix/devenv/latest";
      url = "github:nazarewk/devenv/flake-parts-container-usage";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";

      inputs.pre-commit-hooks.follows = "pre-commit-hooks";
      inputs.nix.follows = "devenv-nix"; # url = "github:domenkozar/nix/relaxed-flakes";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
      };
    };

    devenv-nix = {
      url = "github:domenkozar/nix/relaxed-flakes";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mk-shell-bin = {
      url = "github:rrbutani/nix-mk-shell-bin";
    };

    #atuin = {
    #  url = "github:ellie/atuin";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #  inputs.flake-compat.follows = "flake-compat";
    #  inputs.flake-utils.follows = "flake-utils";
    #};

    nix-on-droid = {
      url = "github:t184256/nix-on-droid/release-22.11";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
      imports = [
        inputs.devenv.flakeModule
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
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
            # adds nixosConfigurations as microvms as packages with microvm-* prefix
            # TODO: fix /nix/store filesystem type conflict before re-enabling
            #(lib.attrsets.mapAttrs' (name: value: lib.attrsets.nameValuePair "microvm-${name}" value) (flakeLib.microvm.packages system))
          ];

          devenv.shells.default = {
            name = "default";

            # https://devenv.sh/reference/options/
            packages = with pkgs; [
              argo
              kubectl
              git
              vim
              gnupg
            ];
          };
        };
      flake = {
        inherit lib;

        apps = inputs.nixinate.nixinate."x86_64-linux" self;

        overlays.default = lib.composeManyExtensions [
          poetry2nix.overlay
          (final: prev: lib.concatMapAttrs
            (name: { input ? name, package ? name }: {
              ${name} = inputs.${input}.packages.${final.stdenv.system}.${package};
            })
            {
              devenv = { };
              #atuin = { };
            })
          (final: prev: {
            # work around not using flake-utils which sets it up on `pkgs.system`
            # see https://github.com/numtide/flake-utils/blob/1ed9fb1935d260de5fe1c2f7ee0ebaae17ed2fa1/check-utils.nix#L4
            system = final.stdenv.system;
            lib = import ./lib { inherit (prev) lib; };
          })
          (final: prev: (import ./packages { inherit inputs self; pkgs = prev; }))
          (final: prev: {
            waylandPkgs = self.inputs.nixpkgs-wayland.packages.${final.stdenv.system};
          })
        ];
        nixosModules.default = ./modules;

        nixosConfigurations = lib.mkMerge [
          {
            oams = flakeLib.nixos.system {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.oams.enable = true; }
                {
                  system.stateVersion = "23.11";
                  networking.hostId = "ce0f2f33"; # cut -c-8 </proc/sys/kernel/random/uuid
                  networking.hostName = "oams";

                  _module.args.nixinate = {
                    host = "oams";
                    sshUser = "kdn";
                    buildOn = "local"; # valid args are "local" or "remote"
                    substituteOnTarget = false; # if buildOn is "local" then it will substitute on the target, "-s"
                    hermetic = true;
                    nixOptions = [ "--show-trace" ];
                  };
                }];
            };

            krul = flakeLib.nixos.system {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.krul.enable = true; }
                {
                  system.stateVersion = "23.11";
                  networking.hostId = "81d86976"; # cut -c-8 </proc/sys/kernel/random/uuid
                  networking.hostName = "krul";

                  _module.args.nixinate = {
                    host = "krul";
                    sshUser = "kdn";
                    buildOn = "local"; # valid args are "local" or "remote"
                    substituteOnTarget = false; # if buildOn is "local" then it will substitute on the target, "-s"
                    hermetic = true;
                    nixOptions = [ "--show-trace" ];
                  };
                }];
            };

            obler = flakeLib.nixos.system {
              system = "x86_64-linux";
              modules = [{ kdn.profile.host.obler.enable = true; }
                {
                  system.stateVersion = "23.11";
                  networking.hostId = "f6345d38"; # cut -c-8 </proc/sys/kernel/random/uuid
                  networking.hostName = "obler";

                  _module.args.nixinate = {
                    host = "obler";
                    sshUser = "kdn";
                    buildOn = "local"; # valid args are "local" or "remote"
                    substituteOnTarget = false; # if buildOn is "local" then it will substitute on the target, "-s"
                    hermetic = true;
                    nixOptions = [ "--show-trace" ];
                  };
                }];
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



        nixOnDroidConfigurations.default =
          let inherit (inputs) nix-on-droid home-manager;
          in nix-on-droid.lib.nixOnDroidConfiguration {
            modules = [
              ./machines/irp/nix-on-droid.nix
            ];

            extraSpecialArgs = {
              # rootPath = ./.;
            };

            pkgs = import nixpkgs {
              system = "aarch64-linux";
              overlays = [
                nix-on-droid.overlays.default
                self.overlays.default
              ];
            };

            # set path to home-manager flake
            home-manager-path = home-manager.outPath;
          };
      };
    });
}
