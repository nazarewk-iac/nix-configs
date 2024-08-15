{
  #inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixpkgs.url = "github:nazarewk/nixpkgs/nixos-unstable";
  #inputs.nixpkgs.url = "github:nazarewk/nixpkgs/hardware-firmware-edid-fix";
  inputs.nixpkgs-lib.url = "github:NixOS/nixpkgs/nixos-unstable?dir=lib";

  /*
   * pinned inputs to keep up to date manually
   */
  inputs.helix-editor.url = "github:helix-editor/helix/24.07";

  /*
   * rest of inputs
   */
  inputs.base16-foot.flake = false;
  inputs.base16-foot.url = "github:tinted-theming/base16-foot";
  inputs.base16.url = "github:SenchoPens/base16.nix";
  inputs.crane.url = "github:ipetkov/crane";
  inputs.disko.url = "github:nix-community/disko";
  inputs.empty.url = "github:nix-systems/empty";
  inputs.flake-compat.url = "github:edolstra/flake-compat";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.impermanence.url = "github:nix-community/impermanence";
  inputs.lanzaboote.url = "github:nix-community/lanzaboote";
  inputs.microvm.url = "github:astro/microvm.nix";
  inputs.mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
  inputs.nix-eval-jobs.url = "github:nix-community/nix-eval-jobs";
  inputs.nix-github-actions.url = "github:nix-community/nix-github-actions";
  inputs.nixinate.url = "github:matthewcroughan/nixinate";
  inputs.nixos-anywhere.url = "github:numtide/nixos-anywhere";
  inputs.nixos-generators.url = "github:nix-community/nixos-generators";
  inputs.nur.url = "github:nix-community/NUR";
  inputs.poetry2nix.url = "github:nix-community/poetry2nix";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.sops-nix.url = "github:Mic92/sops-nix";
  inputs.stylix.url = "github:danth/stylix";
  inputs.systems.url = "github:nix-systems/default";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.ulauncher.url = "github:Ulauncher/Ulauncher/v6";

  /*
   * dependencies
   */
  inputs.crane.inputs.nixpkgs.follows = "nixpkgs";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib";
  inputs.helix-editor.inputs.crane.follows = "crane";
  inputs.helix-editor.inputs.flake-utils.follows = "flake-utils";
  inputs.helix-editor.inputs.nixpkgs.follows = "nixpkgs";
  inputs.helix-editor.inputs.rust-overlay.follows = "rust-overlay";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";
  inputs.lanzaboote.inputs.crane.follows = "crane";
  inputs.lanzaboote.inputs.flake-compat.follows = "flake-compat";
  inputs.lanzaboote.inputs.flake-parts.follows = "flake-parts";
  inputs.lanzaboote.inputs.nixpkgs.follows = "nixpkgs";
  inputs.lanzaboote.inputs.pre-commit-hooks-nix.follows = "empty";
  inputs.lanzaboote.inputs.rust-overlay.follows = "rust-overlay";
  inputs.microvm.inputs.flake-utils.follows = "flake-utils";
  inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-eval-jobs.inputs.flake-parts.follows = "flake-parts";
  inputs.nix-eval-jobs.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixinate.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixos-anywhere.inputs.disko.follows = "disko";
  inputs.nixos-anywhere.inputs.flake-parts.follows = "flake-parts";
  inputs.nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixos-anywhere.inputs.treefmt-nix.follows = "treefmt-nix";
  inputs.nixos-generators.inputs.nixlib.follows = "nixpkgs-lib";
  inputs.nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
  inputs.poetry2nix.inputs.flake-utils.follows = "flake-utils";
  inputs.poetry2nix.inputs.nix-github-actions.follows = "nix-github-actions";
  inputs.poetry2nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.poetry2nix.inputs.treefmt-nix.follows = "treefmt-nix";
  inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  inputs.sops-nix.inputs.nixpkgs-stable.follows = "empty";
  inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.stylix.inputs.base16-foot.follows = "base16-foot";
  inputs.stylix.inputs.flake-compat.follows = "flake-compat";
  inputs.stylix.inputs.home-manager.follows = "home-manager";
  inputs.stylix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.ulauncher.inputs.flake-parts.follows = "flake-parts";
  inputs.ulauncher.inputs.nixpkgs.follows = "nixpkgs";

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
        inputs.nur.overlay
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
                    home-manager.sharedModules = [{ home.stateVersion = "24.11"; }];
                    kdn.security.secrets.allow = false;
                    kdn.profile.machine.baseline.enable = true;
                    kdn.profile.machine.baseline.netbird-priv.type = "ephemeral";

                    environment.systemPackages = with pkgs; [
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
                home-manager.sharedModules = [{ home.stateVersion = "23.11"; }];
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
                system.stateVersion = "24.11";
                home-manager.sharedModules = [{ home.stateVersion = "24.11"; }];
                networking.hostId = "0a989258"; # cut -c-8 </proc/sys/kernel/random/uuid
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

          etra = flakeLib.nixos.system {
            system = "x86_64-linux";
            modules = [{ kdn.profile.host.etra.enable = true; }
              {
                system.stateVersion = "24.11";
                home-manager.sharedModules = [{ home.stateVersion = "24.11"; }];
                networking.hostId = "6dc8c4d7"; # cut -c-8 </proc/sys/kernel/random/uuid
                networking.hostName = "etra";

                _module.args.nixinate = {
                  #host = "etra.lan.";
                  host = "etra.netbird.cloud.";
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
                home-manager.sharedModules = [{ home.stateVersion = "23.11"; }];
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
                home-manager.sharedModules = [{ home.stateVersion = "23.11"; }];
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
            home-manager.sharedModules = [{ home.stateVersion = "23.11"; }];
            kdn.profile.machine.baseline.enable = true;
          }];
        })
      ];
    });
}
