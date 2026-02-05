{
  inputs.nixpkgs-upstream.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixpkgs.url = "github:nazarewk/nixpkgs/nixos-unstable";
  inputs.nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

  inputs.nixpkgs-lib.follows = "nixpkgs";

  # * pinned inputs to keep up to date manually
  inputs.helix-editor.url = "github:helix-editor/helix/25.07.1";

  # * rest of inputs

  inputs.angrr.url = "github:linyinfeng/angrr";
  inputs.argon40-nix.url = "github:guusvanmeerveld/argon40-nix";
  inputs.base16.url = "github:SenchoPens/base16.nix";
  inputs.brew-api.flake = false;
  inputs.brew-api.url = "github:BatteredBunny/brew-api";
  inputs.brew-nix.url = "github:BatteredBunny/brew-nix";
  inputs.brew-tap--homebrew--bundle.flake = false;
  inputs.brew-tap--homebrew--bundle.url = "github:homebrew/homebrew-bundle";
  inputs.brew-tap--homebrew--cask.flake = false;
  inputs.brew-tap--homebrew--cask.url = "github:homebrew/homebrew-cask";
  inputs.brew-tap--homebrew--core.flake = false;
  inputs.brew-tap--homebrew--core.url = "github:homebrew/homebrew-core";
  inputs.brew.flake = false;
  inputs.brew.url = "github:Homebrew/brew/4.4.16";
  inputs.colmena.url = "github:zhaofengli/colmena";
  inputs.crane.url = "github:ipetkov/crane";
  inputs.disko.url = "github:nix-community/disko";
  inputs.disko-zfs.url = "github:numtide/disko-zfs";
  inputs.empty.url = "github:nix-systems/empty";
  inputs.easykubenix.url = "github:Lillecarl/easykubenix";
  inputs.easykubenix.flake = false;
  inputs.flake-compat.url = "github:edolstra/flake-compat";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.hardware-report.url = "github:sfcompute/hardware_report";
  inputs.haumea.url = "github:nix-community/haumea";
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.infuse.flake = false;
  inputs.infuse.url = "git+https://codeberg.org/amjoseph/infuse.nix.git";
  inputs.lanzaboote.url = "github:nix-community/lanzaboote";
  inputs.microvm.url = "github:astro/microvm.nix";
  inputs.nix-darwin.url = "github:LnL7/nix-darwin";
  inputs.nix-fast-build.url = "github:Mic92/nix-fast-build";
  inputs.nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  inputs.nixcasks.url = "github:jacekszymanski/nixcasks";
  inputs.nixos-anywhere.url = "github:numtide/nixos-anywhere";
  inputs.nixos-avf-upstream.url = "github:nix-community/nixos-avf";
  inputs.nixos-avf.url = "github:nazarewk/nixos-avf";
  inputs.nixos-generators.url = "github:nix-community/nixos-generators";
  inputs.nixos-hardware.url = "github:nixos/nixos-hardware";
  inputs.nur.url = "github:nix-community/NUR";
  inputs.preservation-upstream.url = "github:nix-community/preservation";
  inputs.preservation.url = "github:nazarewk/preservation/nix-configs";
  inputs.rpi-sbcshop-hat-ups.flake = false;
  inputs.rpi-sbcshop-hat-ups.url = "github:sbcshop/UPS-Hat-RPi";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.stylix.url = "github:danth/stylix";
  inputs.systems.url = "github:nix-systems/default";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.wezterm.url = "github:wez/wezterm/main?dir=nix";

  inputs.sops-nix-upstream.url = "github:Mic92/sops-nix";
  inputs.sops-nix.url = "github:nazarewk/sops-nix";
  inputs.sops-upstream.flake = false;
  inputs.sops-upstream.url = "github:getsops/sops";

  # * dependencies
  inputs.argon40-nix.inputs.flake-utils.follows = "flake-utils";
  inputs.argon40-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.brew-nix.inputs.brew-api.follows = "brew-api";
  inputs.brew-nix.inputs.nix-darwin.follows = "nix-darwin";
  inputs.brew-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.colmena.inputs.flake-compat.follows = "flake-compat";
  inputs.colmena.inputs.flake-utils.follows = "flake-utils";
  inputs.colmena.inputs.nixpkgs.follows = "nixpkgs";
  inputs.colmena.inputs.stable.follows = "nixpkgs-stable";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";
  inputs.disko-zfs.inputs.nixpkgs.follows = "nixpkgs";
  inputs.disko-zfs.inputs.flake-parts.follows = "flake-parts";
  inputs.disko-zfs.inputs.disko.follows = "disko";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib";
  inputs.nix-fast-build.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-fast-build.inputs.flake-parts.follows = "flake-parts";
  inputs.nix-fast-build.inputs.treefmt-nix.follows = "treefmt-nix";
  inputs.hardware-report.inputs.flake-utils.follows = "flake-utils";
  inputs.hardware-report.inputs.nixpkgs.follows = "nixpkgs";
  inputs.hardware-report.inputs.rust-overlay.follows = "rust-overlay";
  inputs.helix-editor.inputs.nixpkgs.follows = "nixpkgs";
  inputs.helix-editor.inputs.rust-overlay.follows = "rust-overlay";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";
  inputs.lanzaboote.inputs.crane.follows = "crane";
  inputs.lanzaboote.inputs.nixpkgs.follows = "nixpkgs";
  inputs.lanzaboote.inputs.pre-commit.follows = "empty";
  inputs.lanzaboote.inputs.rust-overlay.follows = "rust-overlay";
  inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixcasks.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixos-anywhere.inputs.disko.follows = "disko";
  inputs.nixos-anywhere.inputs.flake-parts.follows = "flake-parts";
  inputs.nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixos-anywhere.inputs.treefmt-nix.follows = "treefmt-nix";
  inputs.nixos-avf.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixos-generators.inputs.nixlib.follows = "nixpkgs-lib";
  inputs.nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
  inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.stylix.inputs.flake-parts.follows = "flake-parts";
  inputs.stylix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.stylix.inputs.nur.follows = "nur";
  inputs.stylix.inputs.systems.follows = "systems";
  inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.wezterm.inputs.flake-utils.follows = "flake-utils";
  inputs.wezterm.inputs.nixpkgs.follows = "nixpkgs";
  inputs.wezterm.inputs.rust-overlay.follows = "rust-overlay";

  outputs = inputs @ {
    flake-parts,
    self,
    ...
  }: let
    inherit (self) lib;

    flakeLib = lib.kdn.flakes.forFlake self;
  in (flake-parts.lib.mkFlake {inherit inputs;} {
    systems = import inputs.systems;

    flake.overlays.packages = inputs.nixpkgs.lib.composeManyExtensions [
      (final: prev: {
        kdn =
          (prev.kdn or {})
          // (import ./packages {
            pkgs = final;
            lib = final.lib;
          });
      })
    ];

    flake.overlays.default = inputs.nixpkgs.lib.composeManyExtensions [
      self.overlays.packages
      inputs.nur.overlays.default
      inputs.microvm.overlays.default
      inputs.angrr.overlays.default
      (final: prev: {
        inherit lib;
        kdnConfig = self.kdnMetaModule.config;
      })
      (final: prev: let
        getDefault = input: input.packages."${final.stdenv.hostPlatform.system}".default;
      in {
        nixos-anywhere = getDefault inputs.nixos-anywhere;
        nix-fast-build = getDefault inputs.nix-fast-build;
      })
      (
        final: prev: let
          src = "${inputs.nixcasks}";
          pkgs = prev;
          sevenzip = prev.callPackage "${src}/7zip" {inherit pkgs;};
          nclib = import "${src}/nclib.nix" {inherit pkgs sevenzip;};

          originalCasks = (inputs.nixcasks.output {osVersion = "tahoe";}).packages.${prev.stdenv.hostPlatform.system};

          overrides =
            lib.pipe
            [
            ]
            [
              (map (name: {
                inherit name;
                value = originalCasks."${name}".overrideAttrs nclib.force-dmg;
              }))
              builtins.listToAttrs
            ];
        in
          if !prev.stdenv.isDarwin
          then {}
          else
            (inputs.brew-nix.overlays.default final prev)
            // {
              nclib =
                nclib
                // {
                  inherit sevenzip;
                };
              nixcasks = originalCasks // overrides;
            }
      )
    ];
    flake.self = self;
    flake.lib = inputs.nixpkgs.lib.extend self.libOverlay;
    flake.libOverlay = final: prev: {
      kdn = import ./lib {lib = final;};
      infuse = (import "${inputs.infuse.outPath}/default.nix" {lib = final;}).v1.infuse;
      disko = inputs.disko.lib;
      darwin = inputs.nix-darwin.lib;
      colmena = inputs.colmena.lib;
      inherit (inputs.nix-darwin.lib) darwinSystem;
      inherit (inputs.home-manager.lib) hm homeManagerConfiguration;
    };

    flake.kdnMetaModule = lib.evalModules {
      class = "kdn-meta";
      modules = [
        ./modules/meta
        {
          inherit inputs lib self;
          nix-configs = self;
        }
      ];
    };
    flake.hostConfigurations = lib.pipe ./hosts [
      builtins.readDir
      (builtins.mapAttrs (entry: _: let
        dir = lib.path.append ./hosts entry;
        json = lib.path.append dir "meta.json";
        nix = lib.path.append dir "meta.nix";

        has.json = builtins.pathExists json;
        has.nix = builtins.pathExists nix;
        has.module = builtins.pathExists (lib.path.append dir "default.nix");
      in
        if has.module && (has.json || has.nix)
        then
          self.kdnMetaModule.config.output.mkSubmodule {
            imports = lib.lists.optional has.nix nix;
            config = lib.mkMerge [
              {modules = [dir];}
              (lib.mkIf has.json (builtins.fromJSON (builtins.readFile json)))
            ];
          }
        else {}))
      (lib.attrsets.filterAttrs (_: host: host != {}))
    ];
    flake.hosts = lib.attrsets.mapAttrs (_: value: value.config) (self.darwinConfigurations // self.nixosConfigurations);
    flake.nixosModules.default = ./modules/nixos;
    flake.nixosConfigurations = lib.pipe self.hostConfigurations [
      (lib.attrsets.filterAttrs (_: host: host.moduleType == "nixos"))
      (builtins.mapAttrs (_: host:
        lib.nixosSystem {
          inherit (host) system specialArgs;
          modules =
            host.modules
            ++ [
              ({kdnConfig, ...}: {config.kdn.hostName = lib.mkDefault kdnConfig.hostName;})
            ];
        }))
    ];
    flake.darwinModules.default = ./modules/darwin;
    flake.darwinConfigurations = lib.pipe self.hostConfigurations [
      (lib.attrsets.filterAttrs (_: host: host.moduleType == "darwin"))
      (builtins.mapAttrs (_: host:
        lib.darwinSystem {
          inherit (host) lib specialArgs;
          system = null;
          modules =
            host.modules
            ++ [
              {nixpkgs.system = host.system;}
              ({kdnConfig, ...}: {config.kdn.hostName = lib.mkDefault kdnConfig.hostName;})
            ];
        }))
    ];

    flake.colmena =
      lib.infuse {
        meta.nixpkgs = import inputs.nixpkgs {
          system = "x86_64-linux";
          overlays = [self.overlays.default];
        };
        defaults.deployment.targetUser = "kdn";
      }
      (lib.attrsets.mapAttrsToList (name: module: let
          host = self.hostConfigurations."${name}";
        in {
          meta.nodeSpecialArgs."${name}".__init = host.specialArgs;
          meta.nodeNixpkgs."${name}".__init = import inputs.nixpkgs {
            inherit (host.specialArgs.kdnConfig) system;
            overlays = [self.overlays.default];
          };
          "${name}".__init = {
            imports =
              host.modules
              ++ [
                module
                ({kdnConfig, ...}: {
                  config.kdn.hostName = lib.mkDefault kdnConfig.hostName;
                })
              ];
          };
        })
        {
          etra.deployment.targetHost = "etra.lan.etra.net.int.kdn.im.";
          pwet.deployment.targetHost = "pwet.pic.etra.net.int.kdn.im.";
          turo.deployment.targetHost = "turo.pic.etra.net.int.kdn.im.";
          yost.deployment.targetHost = "yost.pic.etra.net.int.kdn.im.";
        });
    flake.colmenaHive = lib.colmena.makeHive self.colmena;
    flake.mkEasykubenix = system: modules:
      import inputs.easykubenix {
        inherit modules;
        pkgs = inputs.nixpkgs.legacyPackages.${system}.extend self.overlays.default;
        specialArgs = (self.kdnMetaModule.config.output.mkSubmodule {moduleType = "easykubenix";}).specialArgs;
      };

    perSystem = {
      config,
      self',
      inputs',
      system,
      pkgs,
      ...
    }: {
      _module.args.pkgs = inputs'.nixpkgs.legacyPackages.extend self.overlays.default;
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
      apps.update = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "flake-update";
            runtimeInputs = with pkgs; [
              # TODO: add `update.py` dependency here
              git
              gnugrep
              pass
              python3
            ];
            text = builtins.readFile ./flake-update.sh;
          }
        );
      };
      apps.colmena = inputs'.colmena.apps.default;
      apps.nix-fast-build = {
        type = "app";
        program = lib.getExe inputs'.nix-fast-build.packages.default;
      };
      apps.disko-zfs = {
        type = "app";
        program = lib.getExe inputs'.disko-zfs.packages.default;
      };
      checks = pkgs.callPackages ./checks (self.kdnMetaModule {
        moduleType = "checks";
      });
      devShells = {};
      packages = lib.mkMerge [
        (
          lib.filterAttrs (n: pkg: lib.isDerivation pkg)
          (flakeLib.overlayedInputs {inherit system;}).nixpkgs.kdn
        )
        {
          install-iso = inputs.nixos-generators.nixosGenerate {
            format = "install-iso";
            inherit system;
            inherit (self) lib;
            inherit (lib) nixosSystem;
            specialArgs = (self.kdnMetaModule.config.output.mkSubmodule {moduleType = "nixos";}).specialArgs;
            modules = [./hosts/install-iso];
          };
        }
      ];
    };
  });
}
