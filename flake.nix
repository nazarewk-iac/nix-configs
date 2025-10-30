{
  inputs.nixpkgs-upstream.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixpkgs.url = "github:nazarewk/nixpkgs/nixos-unstable";

  inputs.nixpkgs-lib.follows = "nixpkgs";

  # * pinned inputs to keep up to date manually
  inputs.helix-editor.url = "github:helix-editor/helix/25.07.1";

  # * rest of inputs

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
  inputs.rpi-sbcshop-hat-ups.flake = false;
  inputs.rpi-sbcshop-hat-ups.url = "github:sbcshop/UPS-Hat-RPi";
  inputs.crane.url = "github:ipetkov/crane";
  inputs.disko.url = "github:nix-community/disko";
  inputs.empty.url = "github:nix-systems/empty";
  inputs.flake-compat.url = "github:edolstra/flake-compat";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.haumea.url = "github:nix-community/haumea";
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.lanzaboote.url = "github:nix-community/lanzaboote";
  inputs.microvm.url = "github:astro/microvm.nix";
  inputs.nix-darwin.url = "github:LnL7/nix-darwin";
  inputs.nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  inputs.nixcasks.url = "github:jacekszymanski/nixcasks";
  inputs.nixos-anywhere.url = "github:numtide/nixos-anywhere";
  inputs.nixos-generators.url = "github:nix-community/nixos-generators";
  inputs.nur.url = "github:nix-community/NUR";
  inputs.preservation.url = "github:nazarewk/preservation/nix-configs";
  inputs.preservation-upstream.url = "github:nix-community/preservation";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.nixos-hardware.url = "github:nixos/nixos-hardware";
  inputs.stylix.url = "github:danth/stylix";
  inputs.systems.url = "github:nix-systems/default";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.wezterm.url = "github:wez/wezterm/main?dir=nix";

  #inputs.sops-nix.url = "github:Mic92/sops-nix";
  inputs.sops-nix.url = "github:brianmcgee/sops-nix/feat/age-plugins";
  inputs.sops-upstream.flake = false;
  inputs.sops-upstream.url = "github:getsops/sops";

  # * dependencies
  inputs.argon40-nix.inputs.flake-utils.follows = "flake-utils";
  inputs.argon40-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.brew-nix.inputs.brew-api.follows = "brew-api";
  inputs.brew-nix.inputs.nix-darwin.follows = "nix-darwin";
  inputs.brew-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib";
  inputs.helix-editor.inputs.nixpkgs.follows = "nixpkgs";
  inputs.helix-editor.inputs.rust-overlay.follows = "rust-overlay";
  inputs.haumea.inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";
  inputs.lanzaboote.inputs.crane.follows = "crane";
  inputs.lanzaboote.inputs.flake-compat.follows = "flake-compat";
  inputs.lanzaboote.inputs.flake-parts.follows = "flake-parts";
  inputs.lanzaboote.inputs.nixpkgs.follows = "nixpkgs";
  inputs.lanzaboote.inputs.pre-commit-hooks-nix.follows = "empty";
  inputs.lanzaboote.inputs.rust-overlay.follows = "rust-overlay";
  inputs.microvm.inputs.flake-utils.follows = "flake-utils";
  inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixcasks.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixos-anywhere.inputs.disko.follows = "disko";
  inputs.nixos-anywhere.inputs.flake-parts.follows = "flake-parts";
  inputs.nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixos-anywhere.inputs.treefmt-nix.follows = "treefmt-nix";
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
    lib = import ./lib {inherit (inputs.nixpkgs) lib;};
    flakeLib = lib.kdn.flakes.forFlake self;
    kdnModule = lib.evalModules {
      class = "kdn-meta";
      modules = [
        ./modules/meta
        {
          inherit inputs lib self;
          nix-configs = self;
        }
      ];
    };
    mkSpecialArgs = kdnModule.config.output.mkSubmodule;
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
      (final: prev: {inherit lib;})
      (final: prev: {nixos-anywhere = inputs.nixos-anywhere.packages."${final.stdenv.system}".default;})
      (
        final: prev:
          if prev.stdenv.isDarwin
          then inputs.brew-nix.overlays.default final prev
          else {}
      )
      (
        final: prev:
          if prev.stdenv.isDarwin
          then let
            src = "${inputs.nixcasks}";
            pkgs = prev;
            sevenzip = prev.darwin.apple_sdk_11_0.callPackage "${src}/7zip" {inherit pkgs;};
            nclib = import "${src}/nclib.nix" {inherit pkgs sevenzip;};

            originalCasks = (inputs.nixcasks.output {osVersion = "tahoe";}).packages.${prev.stdenv.system};

            overrides =
              lib.pipe
              [
              ]
              [
                (builtins.map (name: {
                  inherit name;
                  value = originalCasks."${name}".overrideAttrs nclib.force-dmg;
                }))
                builtins.listToAttrs
              ];
          in {
            nclib =
              nclib
              // {
                inherit sevenzip;
              };
            nixcasks = originalCasks // overrides;
          }
          else {}
      )
    ];
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
      checks = pkgs.callPackages ./checks (mkSpecialArgs {
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
            specialArgs = mkSpecialArgs {moduleType = "nixos";};

            modules = [
              self.nixosModules.default
              {
                /*
                `image.baseName` gives a stable image filename
                - see https://github.com/NixOS/nixpkgs/blob/30a61f056ac492e3b7cdcb69c1e6abdcf00e39cf/nixos/modules/image/file-options.nix#L9-L16
                */
                image.baseName = lib.mkForce "kdn-nixos-install-iso";

                /*
                 `install-iso` uses some weird GRUB booting chimera
                see https://github.com/NixOS/nixpkgs/blob/9fbeebcc35c2fbc9a3fb96797cced9ea93436097/nixos/modules/installer/cd-dvd/iso-image.nix#L780-L787
                */
                boot.initrd.systemd.enable = lib.mkForce false;
                boot.loader.systemd-boot.enable = lib.mkForce false;
              }
              {
                kdn.hostName = "kdn-nixos-install-iso";
                home-manager.sharedModules = [{home.stateVersion = "24.11";}];
                kdn.security.secrets.allow = true;
                kdn.profile.machine.baseline.enable = true;
                kdn.security.disk-encryption.enable = true;
                kdn.networking.netbird.clients.priv.type = "ephemeral";

                environment.systemPackages = with pkgs; [
                ];
              }
              (
                {config, ...}: {
                  users.users.root.openssh.authorizedKeys.keys = config.users.users.kdn.openssh.authorizedKeys.keys;
                }
              )
            ];
          };
        }
      ];
    };
    flake.lib = lib;
    flake.nixosModules.default = ./modules/nixos;
    flake.nixosConfigurations = lib.mkMerge [
      {
        oams = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = mkSpecialArgs {
            moduleType = "nixos";
          };
          modules = [
            self.nixosModules.default
            (
              {config, ...}: {
                kdn.hostName = "oams";
                kdn.profile.host."${config.kdn.hostName}".enable = true;

                system.stateVersion = "23.11";
                home-manager.sharedModules = [{home.stateVersion = "23.11";}];
                networking.hostId = "ce0f2f33"; # cut -c-8 </proc/sys/kernel/random/uuid
              }
            )
          ];
        };

        brys = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = mkSpecialArgs {
            moduleType = "nixos";
            features.microvm-host = true;
          };
          modules = [
            self.nixosModules.default
            (
              {config, ...}: {
                kdn.hostName = "brys";
                kdn.profile.host."${config.kdn.hostName}".enable = true;

                system.stateVersion = "24.11";
                home-manager.sharedModules = [{home.stateVersion = "24.11";}];
                networking.hostId = "0a989258"; # cut -c-8 </proc/sys/kernel/random/uuid
              }
            )
          ];
        };

        etra = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = mkSpecialArgs {
            moduleType = "nixos";
          };
          modules = [
            self.nixosModules.default
            (
              {config, ...}: {
                kdn.hostName = "etra";
                kdn.profile.host."${config.kdn.hostName}".enable = true;

                system.stateVersion = "24.11";
                home-manager.sharedModules = [{home.stateVersion = "24.11";}];
                networking.hostId = "6dc8c4d7"; # cut -c-8 </proc/sys/kernel/random/uuid
              }
            )
          ];
        };

        pryll = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = mkSpecialArgs {
            moduleType = "nixos";
          };
          modules = [
            self.nixosModules.default
            (
              {config, ...}: {
                kdn.hostName = "pryll";
                kdn.profile.host."${config.kdn.hostName}".enable = true;

                system.stateVersion = "25.05";
                home-manager.sharedModules = [{home.stateVersion = "25.05";}];
                networking.hostId = "25880d1d"; # cut -c-8 </proc/sys/kernel/random/uuid
              }
            )
          ];
        };

        obler = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = mkSpecialArgs {
            moduleType = "nixos";
          };
          modules = [
            self.nixosModules.default
            (
              {config, ...}: {
                kdn.hostName = "obler";
                kdn.profile.host."${config.kdn.hostName}".enable = true;

                system.stateVersion = "23.11";
                home-manager.sharedModules = [{home.stateVersion = "23.11";}];
                networking.hostId = "f6345d38"; # cut -c-8 </proc/sys/kernel/random/uuid
              }
            )
          ];
        };

        moss = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = mkSpecialArgs {
            moduleType = "nixos";
          };
          modules = [
            self.nixosModules.default
            (
              {config, ...}: {
                kdn.hostName = "moss";
                kdn.profile.host."${config.kdn.hostName}".enable = true;

                system.stateVersion = "23.11";
                home-manager.sharedModules = [{home.stateVersion = "23.11";}];
                networking.hostId = "550ded62"; # cut -c-8 </proc/sys/kernel/random/uuid
              }
            )
            (
              {modulesPath, ...}: {
                imports = [
                  (modulesPath + "/profiles/qemu-guest.nix")
                  (modulesPath + "/profiles/headless.nix")
                ];
              }
            )
          ];
        };

        faro = lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = mkSpecialArgs {
            moduleType = "nixos";
            features.darwin-utm-guest = true;
          };
          modules = [
            self.nixosModules.default
            (
              {config, ...}: {
                kdn.hostName = "faro";
                kdn.profile.host."${config.kdn.hostName}".enable = true;

                system.stateVersion = "25.05";
                home-manager.sharedModules = [{home.stateVersion = "25.05";}];
                networking.hostId = "4b2dd30f"; # cut -c-8 </proc/sys/kernel/random/uuid
              }
            )
          ];
        };

        briv = lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = mkSpecialArgs {
            moduleType = "nixos";
            features.rpi4 = true;
          };
          modules = [
            self.nixosModules.default
            (
              {config, ...}: {
                kdn.hostName = "briv";
                kdn.profile.host."${config.kdn.hostName}".enable = true;

                system.stateVersion = "25.05";
                home-manager.sharedModules = [{home.stateVersion = "25.05";}];
                networking.hostId = "b86e74e8"; # cut -c-8 </proc/sys/kernel/random/uuid
              }
            )
          ];
        };

        rpi4-bootstrap = lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = mkSpecialArgs {
            moduleType = "nixos";
            features.rpi4 = true;
          };
          modules = [
            self.nixosModules.default
            (
              {config, ...}: {
                kdn.hostName = "kdn-rpi4-bootstrap";
                kdn.profile.host."${config.kdn.hostName}".enable = true;

                system.stateVersion = "25.05";
                home-manager.sharedModules = [{home.stateVersion = "25.05";}];
                networking.hostId = "9751227f"; # cut -c-8 </proc/sys/kernel/random/uuid
              }
            )
          ];
        };
      }
    ];
    flake.darwinModules.default = ./modules/nix-darwin;
    flake.darwinConfigurations.anji = inputs.nix-darwin.lib.darwinSystem {
      specialArgs = mkSpecialArgs {moduleType = "darwin";};
      modules = [
        self.darwinModules.default
        {kdn.hostName = "anji";}
      ];
    };
    flake.self = self;
  });
}
