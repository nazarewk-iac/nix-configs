{
  inputs = {
    #nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs.url = "github:nazarewk/nixpkgs/nixos-unstable";
    #nixpkgs.url = "github:nazarewk/nixpkgs/hardware-firmware-edid-fix";
    nixpkgs-lib.url = "github:NixOS/nixpkgs/nixos-unstable?dir=lib";

    base16.url = "github:SenchoPens/base16.nix";
    crane.inputs.nixpkgs.follows = "nixpkgs";
    crane.url = "github:ipetkov/crane";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-utils.url = "github:numtide/flake-utils";
    helix-editor.inputs.crane.follows = "crane";
    helix-editor.inputs.flake-utils.follows = "flake-utils";
    helix-editor.inputs.nixpkgs.follows = "nixpkgs";
    helix-editor.inputs.rust-overlay.follows = "rust-overlay";
    helix-editor.url = "github:helix-editor/helix/24.03";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    microvm.inputs.flake-utils.follows = "flake-utils";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
    microvm.url = "github:astro/microvm.nix";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    nix-eval-jobs.inputs.flake-parts.follows = "flake-parts";
    nix-eval-jobs.inputs.nixpkgs.follows = "nixpkgs";
    nix-eval-jobs.url = "github:nix-community/nix-eval-jobs";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";
    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nixinate.inputs.nixpkgs.follows = "nixpkgs";
    nixinate.url = "github:matthewcroughan/nixinate";
    nixos-anywhere.inputs.disko.follows = "disko";
    nixos-anywhere.inputs.flake-parts.follows = "flake-parts";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
    nixos-anywhere.inputs.treefmt-nix.follows = "treefmt-nix";
    nixos-anywhere.url = "github:numtide/nixos-anywhere";
    nixos-generators.inputs.nixlib.follows = "nixpkgs-lib";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nur.url = "github:nix-community/NUR";
    poetry2nix.inputs.flake-utils.follows = "flake-utils";
    poetry2nix.inputs.nix-github-actions.follows = "nix-github-actions";
    poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
    poetry2nix.inputs.treefmt-nix.follows = "treefmt-nix";
    poetry2nix.url = "github:nix-community/poetry2nix";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    stylix.inputs.base16-foot.follows = "base16-foot";
    stylix.inputs.flake-compat.follows = "flake-compat";
    stylix.inputs.home-manager.follows = "home-manager";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    stylix.url = "github:danth/stylix";
    systems.url = "github:nix-systems/default";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    ulauncher.inputs.flake-parts.follows = "flake-parts";
    ulauncher.inputs.nixpkgs.follows = "nixpkgs";
    ulauncher.url = "github:Ulauncher/Ulauncher/v6";

    # themes
    base16-foot.flake = false;
    base16-foot.url = "github:tinted-theming/base16-foot";
  };

  outputs =
    inputs@{ flake-parts, self, ... }:
    let
      inherit (inputs) home-manager nixpkgs disko;
      lib = import ./lib { inherit (inputs.nixpkgs) lib; };
      flakeLib = lib.kdn.flakes.forFlake self;
    in
    (flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      flake.overlays.default = (inputs.nixpkgs.lib.composeManyExtensions [
        inputs.poetry2nix.overlays.default
        inputs.ulauncher.overlays.default
        inputs.helix-editor.overlays.default
        (final: prev: {
          kdn = final.callPackages ./packages { };
          inherit lib;
        })
        (final: prev: {
          nixos-anywhere = inputs.nixos-anywhere.packages."${final.stdenv.system}".default;
        })
      ]);
      perSystem = { config, self', inputs', system, pkgs, ... }:
        let kdnNixpkgs = inputs'.nixpkgs.legacyPackages.extend self.overlays.default; in {
          _module.args.pkgs = kdnNixpkgs;
          # inspired by https://github.com/NixOS/nix/issues/3803#issuecomment-748612294
          # usage: nix run '.#repl'
          apps.repl = {
            type = "app";
            program = "${pkgs.writeShellScriptBin "repl" ''
            confnix=$(mktemp)
            trap "rm '$confnix' || true" EXIT
            echo "builtins.getFlake (toString "$PWD")" >$confnix
            nix repl "$confnix" "$@"
          ''}/bin/repl";
          };
          checks = { };
          devShells = { };
          packages = lib.mkMerge [
            (lib.filterAttrs (n: pkg: lib.isDerivation pkg) (flakeLib.overlayedInputs { inherit system; }).nixpkgs.kdn)
            # adds nixosConfigurations as microvms as packages with microvm-* prefix
            # TODO: fix /nix/store filesystem type conflict before re-enabling
            #(lib.attrsets.mapAttrs' (name: value: lib.attrsets.nameValuePair "microvm-${name}" value) (flakeLib.microvm.packages system))
            {
              install-iso = flakeLib.nixos.install-iso {
                inherit system;
                modules = [
                  {
                    kdn.profile.machine.baseline.enable = true;
                    kdn.filesystems.zfs.enable = true;
                    kdn.hardware.disk-encryption.tools.enable = true;

                    environment.systemPackages = with pkgs; [
                      git
                      jq
                      zfs-prune-snapshots
                      sanoid
                    ];
                  }
                  ({ config, ... }: {
                    users.users.root.openssh.authorizedKeys.keys = config.users.users.kdn.openssh.authorizedKeys.keys;
                  })
                ];
              };
            }
          ];
        };
      flake.lib = lib;
      flake.apps = inputs.nixinate.nixinate."x86_64-linux" self;
      flake.nixosModules.default = ./modules;
      flake.nixosConfigurations = lib.mkMerge [
        {
          oams = flakeLib.nixos.system {
            system = "x86_64-linux";
            modules = [{ kdn.profile.host.oams.enable = true; }
              {
                system.stateVersion = "23.11";
                networking.hostId = "ce0f2f33"; # cut -c-8 </proc/sys/kernel/random/uuid
                networking.hostName = "oams";

                _module.args.nixinate = {
                  #host = "oams";
                  host = "oams.lan.";
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
                  host = "krul.lan.";
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
                  #host = "obler";
                  host = "obler.netbird.cloud";
                  sshUser = "kdn";
                  buildOn = "local"; # valid args are "local" or "remote"
                  substituteOnTarget = false; # if buildOn is "local" then it will substitute on the target, "-s"
                  hermetic = true;
                  nixOptions = [ "--show-trace" ];
                };
              }];
          };

          moss = flakeLib.nixos.system {
            system = "x86_64-linux";
            modules = [{ kdn.profile.host.moss.enable = true; }
              {
                system.stateVersion = "23.11";
                networking.hostId = "550ded62"; # cut -c-8 </proc/sys/kernel/random/uuid
                networking.hostName = "moss";

                _module.args.nixinate = {
                  host = "moss.kdn.im";
                  # host = "10.100.0.1"; # wireguard
                  sshUser = "kdn";
                  buildOn = "local"; # valid args are "local" or "remote"
                  substituteOnTarget = false; # if buildOn is "local" then it will substitute on the target, "-s"
                  hermetic = true;
                  nixOptions = [ "--show-trace" ];
                };
              }
              ({ modulesPath, ... }: {
                imports = [
                  (modulesPath + "/profiles/qemu-guest.nix")
                  (modulesPath + "/profiles/headless.nix")
                ];
              })];
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
            system.stateVersion = "23.11";
            kdn.profile.machine.baseline.enable = true;
          }];
        })
      ];
    });
}
