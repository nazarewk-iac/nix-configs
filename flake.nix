{
  inputs.nixpkgs-upstream.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixpkgs.url = "github:nazarewk/nixpkgs/nixos-unstable";
  inputs.nixpkgs-patch-2.url = "https://github.com/NixOS/nixpkgs/compare/nixos-unstable..nazarewk:netbird-improvements.patch?full_index=1";
  inputs.nixpkgs-patch-2.flake = false;

  inputs.nixpkgs-lib.follows = "nixpkgs";

  inputs.nixpkgs-fish.url = "github:NixOS/nixpkgs/fish";

  /*
  * pinned inputs to keep up to date manually
  */
  inputs.helix-editor.url = "github:helix-editor/helix/24.07";
  # skip https://github.com/tinted-theming/tinted-foot/commit/7ca954e993ee73a7cc9b86c59df4920cc8ff9d34
  # see https://github.com/tinted-theming/tinted-foot/issues/8
  inputs.tinted-foot.flake = false;
  inputs.tinted-foot.url = "github:tinted-theming/tinted-foot/fd1b924b6c45c3e4465e8a849e67ea82933fcbe4";

  /*
  * rest of inputs
  */
  inputs.base16.url = "github:SenchoPens/base16.nix";
  inputs.crane.url = "github:ipetkov/crane";
  inputs.disko.url = "github:nix-community/disko";
  inputs.empty.url = "github:nix-systems/empty";
  inputs.flake-compat.url = "github:edolstra/flake-compat";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.impermanence.url = "github:nazarewk/impermanence"; #"github:nix-community/impermanence";
  inputs.lanzaboote.url = "github:nix-community/lanzaboote";
  inputs.microvm.url = "github:astro/microvm.nix";
  inputs.mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
  inputs.nix-eval-jobs.url = "github:nix-community/nix-eval-jobs";
  inputs.nix-github-actions.url = "github:nix-community/nix-github-actions";
  inputs.nix-patcher.url = "github:katrinafyi/nix-patcher";
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
  inputs.wezterm.url = "github:wez/wezterm/main?dir=nix";

  /*
  * dependencies
  */
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
  inputs.nix-eval-jobs.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-patcher.inputs.nixpkgs.follows = "nixpkgs";
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
  inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.stylix.inputs.flake-compat.follows = "flake-compat";
  inputs.stylix.inputs.home-manager.follows = "home-manager";
  inputs.stylix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.stylix.inputs.tinted-foot.follows = "tinted-foot";
  inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.ulauncher.inputs.flake-parts.follows = "flake-parts";
  inputs.ulauncher.inputs.nixpkgs.follows = "nixpkgs";
  inputs.wezterm.inputs.flake-utils.follows = "flake-utils";
  inputs.wezterm.inputs.nixpkgs.follows = "nixpkgs";
  inputs.wezterm.inputs.rust-overlay.follows = "rust-overlay";

  outputs = inputs @ {
    flake-parts,
    self,
    ...
  }: let
    inherit (inputs) home-manager nixpkgs disko;
    lib = import ./lib {inherit (inputs.nixpkgs) lib;};
    flakeLib = lib.kdn.flakes.forFlake self;
  in (flake-parts.lib.mkFlake {inherit inputs;} {
    systems = import inputs.systems;

    flake.overlays.packages = inputs.nixpkgs.lib.composeManyExtensions [
      inputs.poetry2nix.overlays.default
      (final: prev: {
        kdn = (prev.kdn or {}) // (final.callPackages ./packages {});
      })
    ];

    flake.overlays.default = inputs.nixpkgs.lib.composeManyExtensions [
      inputs.ulauncher.overlays.default
      inputs.helix-editor.overlays.default
      inputs.nur.overlays.default
      self.overlays.packages
      (final: prev: {
        inherit lib;

        nixos-anywhere = inputs.nixos-anywhere.packages."${final.stdenv.system}".default;
        nix-patcher = final.callPackage "${inputs.nix-patcher}/patcher.nix" {
          # see https://github.com/katrinafyi/nix-patcher/issues/4
          nix = final.nixVersions.latest;
        };
        wezterm = inputs.wezterm.packages."${final.stdenv.system}".default;

        fish =
          # supposedly fixes https://github.com/NixOS/nix/issues/11010
          if lib.strings.versionAtLeast prev.fish.version "4.0"
          then builtins.throw "nixpkgs fish is now v4+, remove `flake.overlays.default` entry"
          else inputs.nixpkgs-fish.legacyPackages."${final.stdenv.system}".fish;
      })
    ];
    perSystem = {
      config,
      self',
      inputs',
      system,
      pkgs,
      ...
    }: let
      kdnNixpkgs = inputs'.nixpkgs.legacyPackages.extend self.overlays.default;
    in {
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
      apps.nix-patcher = inputs'.nix-patcher.apps.default;
      apps.nixpkgs-update = {
        type = "app";
        program = lib.getExe (pkgs.writeShellApplication {
          name = "nixpkgs-update";
          runtimeInputs = with pkgs; [
            git
            gnugrep
            nix-patcher
            pass
          ];
          text = builtins.readFile ./nixpkgs-update.sh;
        });
      };
      checks = {};
      devShells = {};
      packages = lib.mkMerge [
        (lib.filterAttrs (n: pkg: lib.isDerivation pkg) (flakeLib.overlayedInputs {inherit system;}).nixpkgs.kdn)
        # adds nixosConfigurations as microvms as packages with microvm-* prefix
        # TODO: fix /nix/store filesystem type conflict before re-enabling
        #(lib.attrsets.mapAttrs' (name: value: lib.attrsets.nameValuePair "microvm-${name}" value) (flakeLib.microvm.packages system))
        {
          install-iso = flakeLib.nixos.install-iso {
            inherit system;
            modules = [
              {
                home-manager.sharedModules = [{home.stateVersion = "24.11";}];
                kdn.security.secrets.allow = false;
                kdn.profile.machine.baseline.enable = true;

                environment.systemPackages = with pkgs; [
                ];
              }
              ({config, ...}: {
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
          modules = [
            ({config, ...}: {
              networking.hostName = "oams";
              kdn.profile.host."${config.networking.hostName}".enable = true;

              system.stateVersion = "23.11";
              home-manager.sharedModules = [{home.stateVersion = "23.11";}];
              networking.hostId = "ce0f2f33"; # cut -c-8 </proc/sys/kernel/random/uuid

              _module.args.nixinate = {
                #host = "${config.networking.hostName}.netbird.cloud.";
                #host = hostName;
                host = "${config.networking.hostName}.lan.etra.net.int.kdn.im";
                sshUser = "kdn";
                buildOn = "local"; # valid args are "local" or "remote"
                substituteOnTarget = false; # if buildOn is "local" then it will substitute on the target, "-s"
                hermetic = true;
                nixOptions = ["--show-trace"];
              };
            })
          ];
        };

        brys = flakeLib.nixos.system {
          system = "x86_64-linux";
          modules = [
            ({config, ...}: {
              networking.hostName = "brys";
              kdn.profile.host."${config.networking.hostName}".enable = true;

              system.stateVersion = "24.11";
              home-manager.sharedModules = [{home.stateVersion = "24.11";}];
              networking.hostId = "0a989258"; # cut -c-8 </proc/sys/kernel/random/uuid

              _module.args.nixinate = {
                #host = "${config.networking.hostName}.netbird.cloud.";
                #host = config.networking.hostName;
                host = "${config.networking.hostName}.lan.etra.net.int.kdn.im";
                sshUser = "kdn";
                buildOn = "local"; # valid args are "local" or "remote"
                substituteOnTarget = false; # if buildOn is "local" then it will substitute on the target, "-s"
                hermetic = true;
                nixOptions = ["--show-trace"];
              };
            })
          ];
        };

        etra = flakeLib.nixos.system {
          system = "x86_64-linux";
          modules = [
            ({config, ...}: {
              networking.hostName = "etra";
              kdn.profile.host."${config.networking.hostName}".enable = true;

              system.stateVersion = "24.11";
              home-manager.sharedModules = [{home.stateVersion = "24.11";}];
              networking.hostId = "6dc8c4d7"; # cut -c-8 </proc/sys/kernel/random/uuid

              _module.args.nixinate = {
                #host = "${config.networking.hostName}.netbird.cloud.";
                host = "${config.networking.hostName}.lan.etra.net.int.kdn.im";
                #host = "192.168.73.1";
                sshUser = "kdn";
                buildOn = "local"; # valid args are "local" or "remote"
                substituteOnTarget = false; # if buildOn is "local" then it will substitute on the target, "-s"
                hermetic = true;
                nixOptions = ["--show-trace"];
              };
            })
          ];
        };

        obler = flakeLib.nixos.system {
          system = "x86_64-linux";
          modules = [
            ({config, ...}: {
              networking.hostName = "obler";
              kdn.profile.host."${config.networking.hostName}".enable = true;

              system.stateVersion = "23.11";
              home-manager.sharedModules = [{home.stateVersion = "23.11";}];
              networking.hostId = "f6345d38"; # cut -c-8 </proc/sys/kernel/random/uuid

              _module.args.nixinate = {
                host = "${config.networking.hostName}.netbird.cloud.";
                #host = "${config.networking.hostName}.lan.etra.net.int.kdn.im";
                sshUser = "kdn";
                buildOn = "local"; # valid args are "local" or "remote"
                substituteOnTarget = false; # if buildOn is "local" then it will substitute on the target, "-s"
                hermetic = true;
                nixOptions = ["--show-trace"];
              };
            })
          ];
        };

        moss = flakeLib.nixos.system {
          system = "x86_64-linux";
          modules = [
            ({config, ...}: {
              networking.hostName = "moss";
              kdn.profile.host."${config.networking.hostName}".enable = true;

              system.stateVersion = "23.11";
              home-manager.sharedModules = [{home.stateVersion = "23.11";}];
              networking.hostId = "550ded62"; # cut -c-8 </proc/sys/kernel/random/uuid

              _module.args.nixinate = {
                host = "${config.networking.hostName}.kdn.im";
                #host = "${config.networking.hostName}.netbird.cloud";
                sshUser = "kdn";
                buildOn = "local"; # valid args are "local" or "remote"
                substituteOnTarget = false; # if buildOn is "local" then it will substitute on the target, "-s"
                hermetic = true;
                nixOptions = ["--show-trace"];
              };
            })
            ({modulesPath, ...}: {
              imports = [
                (modulesPath + "/profiles/qemu-guest.nix")
                (modulesPath + "/profiles/headless.nix")
              ];
            })
          ];
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
        modules = [
          {
            system.stateVersion = "23.11";
            home-manager.sharedModules = [{home.stateVersion = "23.11";}];
            kdn.profile.machine.baseline.enable = true;
          }
        ];
      })
    ];
  });
}
