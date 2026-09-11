{
  inputs.nixpkgs-upstream.flake = false; # no need for upstream to be a flake
  inputs.nixpkgs-upstream.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixpkgs.url = "github:nazarewk-iac/nixpkgs/nixos-unstable";
  inputs.nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

  # NOTE FOR AN EXTERNAL ADOPTER
  # `nixpkgs` points at a personal fork of nixos-unstable. The fork carries only the patches that
  # `.flake.patches/config.toml` declares. When no patch is active, its revision and its narHash
  # equal `nixpkgs-upstream`. To use your own tree, set this in your own flake:
  #   inputs.nix-configs.inputs.nixpkgs.follows = "nixpkgs";
  # Four more inputs use the same pattern: `nixos-avf`, `nixos-crostini`, `preservation` and
  # `sops-nix`. Each one takes an `nixpkgs`-style override.
  #
  # Every `*-upstream` input is an anchor for `.flake.patches/update.py`. No output reads one, and
  # `.#sources` drops them. They cost an adopter one extra fetch each.

  inputs.nixpkgs-lib.follows = "nixpkgs";

  # * pinned inputs to keep up to date manually
  inputs.helix-editor.url = "github:helix-editor/helix/25.07.1";

  # * rest of inputs
  inputs.brew-tap--browsers-software--homebrew-tap.flake = false;
  inputs.brew-tap--browsers-software--homebrew-tap.url = "github:Browsers-software/homebrew-tap";

  inputs.angrr.url = "github:linyinfeng/angrr";
  inputs.argon40-nix.url = "github:guusvanmeerveld/argon40-nix";
  inputs.base16.url = "github:SenchoPens/base16.nix";
  inputs.brew-tap--homebrew--cask.flake = false;
  inputs.brew-tap--homebrew--cask.url = "github:homebrew/homebrew-cask";
  inputs.brew-tap--homebrew--core.flake = false;
  inputs.brew-tap--homebrew--core.url = "github:homebrew/homebrew-core";
  inputs.brew.flake = false;
  inputs.brew.url = "github:Homebrew/brew/5.1.8";
  inputs.colmena.url = "github:zhaofengli/colmena";
  inputs.crane.url = "github:ipetkov/crane";
  # den plus its own dependency. Both hold the exact revision the 004 den spike measured, and den
  # itself declares no flake input. See modules/den/README.md before you move either pin.
  inputs.den.url = "github:denful/den/d50f0fce6fc1a8ba00fd0d310746d0e8ecc2f70d";
  inputs.disko.url = "github:nix-community/disko";
  inputs.devenv.url = "github:cachix/devenv";
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
  # den's core dependency. It must be explicit: den otherwise fetches it with
  # `builtins.fetchTarball` at evaluation time, and no consumer lock records that fetch.
  inputs.nix-effects.flake = false;
  inputs.nix-effects.url = "github:denful/nix-effects/c3c68a45deb892d028711eeff8b80937e30a90dd";
  inputs.nix-fast-build.url = "github:Mic92/nix-fast-build";
  inputs.nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  inputs.nix-rosetta-builder.url = "github:cpick/nix-rosetta-builder";
  inputs.nix-rosetta-builder.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixcasks.url = "github:jacekszymanski/nixcasks";
  inputs.nixos-anywhere.url = "github:numtide/nixos-anywhere";
  inputs.nixos-avf-upstream.flake = false; # no need for upstream to be a flake
  inputs.nixos-avf-upstream.url = "github:nix-community/nixos-avf";
  inputs.nixos-avf.url = "github:nazarewk-iac/nixos-avf";
  inputs.nixos-crostini-upstream.flake = false; # no need for upstream to be a flake
  inputs.nixos-crostini-upstream.url = "github:aldur/nixos-crostini";
  inputs.nixos-crostini.url = "github:nazarewk-iac/nixos-crostini";
  inputs.nixos-generators.url = "github:nix-community/nixos-generators";
  inputs.nixos-hardware.url = "github:nixos/nixos-hardware";
  inputs.nur.url = "github:nix-community/NUR";
  inputs.oh-my-pi.url = "github:can1357/oh-my-pi";
  inputs.pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
  inputs.pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";
  inputs.uv2nix.url = "github:pyproject-nix/uv2nix";
  inputs.preservation-upstream.flake = false; # no need for upstream to be a flake
  inputs.preservation-upstream.url = "github:nix-community/preservation";
  inputs.preservation.url = "github:nazarewk-iac/preservation/nix-configs";
  inputs.rpi-sbcshop-hat-ups.flake = false;
  inputs.rpi-sbcshop-hat-ups.url = "github:sbcshop/UPS-Hat-RPi";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.stylix.url = "github:danth/stylix";
  inputs.systems.url = "github:nix-systems/default";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.wezterm.url = "github:wez/wezterm/main?dir=nix";

  inputs.sops-nix-upstream.flake = false; # no need for upstream to be a flake
  inputs.sops-nix-upstream.url = "github:Mic92/sops-nix";
  inputs.sops-nix.url = "github:nazarewk-iac/sops-nix";

  # * dependencies
  inputs.angrr.inputs.nixpkgs.follows = "nixpkgs";
  inputs.argon40-nix.inputs.flake-utils.follows = "flake-utils";
  inputs.argon40-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.colmena.inputs.flake-compat.follows = "flake-compat";
  inputs.colmena.inputs.flake-utils.follows = "flake-utils";
  inputs.colmena.inputs.nixpkgs.follows = "nixpkgs";
  inputs.colmena.inputs.stable.follows = "nixpkgs-stable";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";
  inputs.disko-zfs.inputs.nixpkgs.follows = "nixpkgs";
  inputs.disko-zfs.inputs.flake-parts.follows = "flake-parts";
  inputs.disko-zfs.inputs.disko.follows = "disko";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs-lib";
  inputs.haumea.inputs.nixpkgs.follows = "nixpkgs-lib";
  inputs.nix-fast-build.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-fast-build.inputs.flake-parts.follows = "flake-parts";
  inputs.nix-fast-build.inputs.treefmt-nix.follows = "treefmt-nix";
  inputs.nur.inputs.nixpkgs.follows = "nixpkgs";
  inputs.oh-my-pi.inputs.nixpkgs.follows = "nixpkgs";
  inputs.oh-my-pi.inputs.rust-overlay.follows = "rust-overlay";
  inputs.pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs";
  inputs.pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
  inputs.pyproject-build-systems.inputs.uv2nix.follows = "uv2nix";
  inputs.uv2nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
  inputs.nur.inputs.flake-parts.follows = "flake-parts";
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
  inputs.nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixos-anywhere.inputs.treefmt-nix.follows = "treefmt-nix";
  inputs.nixos-avf.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixos-crostini.inputs.nixpkgs.follows = "nixpkgs";
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

  outputs =
    inputs@{
      flake-parts,
      self,
      ...
    }:
    let
      inherit (self) lib;

      flakeLib = lib.kdn.flakes.forFlake self;
    in
    (flake-parts.lib.mkFlake { inherit inputs; } {
      # `inputs.systems` is `nix-systems/default`, which still lists `x86_64-darwin`. Nixpkgs
      # 26.11 dropped that platform, and every evaluation of it throws "Nixpkgs 26.11 has dropped
      # support for x86_64-darwin". `nix flake check --all-systems` reads each system, so the
      # throw stops the whole check. Measured 2026-09-10. Every Darwin host here is
      # `aarch64-darwin`, so the platform has no use.
      systems = builtins.filter (system: system != "x86_64-darwin") (import inputs.systems);

      # The parallel den tree. It adds outputs and it changes none. See modules/den/README.md.
      imports = [ ./modules/den/flake-module.nix ];

      flake.overlays.packages = inputs.nixpkgs.lib.composeManyExtensions [
        (final: prev: {
          kdn =
            (prev.kdn or { })
            // (import ./packages {
              pkgs = final;
              lib = final.lib;
              kdnConfig = self.kdnMetaModule.config;
              __inputs__ = { inherit inputs; };
            });
        })
      ];

      flake.overlays.default = inputs.nixpkgs.lib.composeManyExtensions [
        self.overlays.packages
        inputs.nur.overlays.default
        inputs.microvm.overlays.default
        inputs.angrr.overlays.default
        inputs.nix-darwin.overlays.default
        inputs.devenv.overlays.default
        inputs.oh-my-pi.overlays.default # provides pkgs.omp
        (final: prev: {
          inherit lib;
          kdnConfig = self.kdnMetaModule.config;
        })
        (
          final: prev:
          let
            getDefault = input: input.packages."${final.stdenv.hostPlatform.system}".default;
          in
          {
            nixos-anywhere = getDefault inputs.nixos-anywhere;
            nix-fast-build = getDefault inputs.nix-fast-build;
          }
        )
        (
          final: prev:
          let
            src = "${inputs.nixcasks}";
            pkgs = prev;
            sevenzip = prev.callPackage "${src}/7zip" { inherit pkgs; };
            nclib = import "${src}/nclib.nix" { inherit pkgs sevenzip; };

            originalCasks =
              (inputs.nixcasks.output { osVersion = "tahoe"; }).packages.${prev.stdenv.hostPlatform.system};

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
          if !prev.stdenv.hostPlatform.isDarwin then
            { }
          else
            {
              nclib = nclib // {
                inherit sevenzip;
              };
              nixcasks = originalCasks // overrides;
            }
        )
      ];
      flake.self = self;
      flake.lib = inputs.nixpkgs.lib.extend self.libOverlay;
      flake.libOverlay = final: prev: {
        kdn = import ./lib { lib = final; };
        infuse = (import "${inputs.infuse.outPath}/default.nix" { lib = final; }).v1.infuse;
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
        (builtins.mapAttrs (
          entry: _:
          let
            dir = lib.path.append ./hosts entry;
            json = lib.path.append dir "meta.json";
            nix = lib.path.append dir "meta.nix";

            has.json = builtins.pathExists json;
            has.nix = builtins.pathExists nix;
            has.module = builtins.pathExists (lib.path.append dir "default.nix");
          in
          if has.module && (has.json || has.nix) then
            self.kdnMetaModule.config.output.mkSubmodule {
              imports = lib.lists.optional has.nix nix;
              config = lib.mkMerge [
                { modules = [ dir ]; }
                (lib.mkIf has.json (builtins.fromJSON (builtins.readFile json)))
              ];
            }
          else
            { }
        ))
        (lib.attrsets.filterAttrs (_: host: host != { }))
      ];
      flake.hosts = lib.attrsets.mapAttrs (_: value: value.config) (
        self.darwinConfigurations // self.nixosConfigurations
      );
      flake.nixosModules.default = ./modules/universal;
      flake.mkSlots =
        { pkgs, ... }@extraModuleArgs:
        let
          extraModule = builtins.removeAttrs extraModuleArgs [ "pkgs" ];
          rendered = lib.kdn.mkSlots {
            slotModules = [
              ./modules/slots
              extraModule
            ];
            specialArgs = {
              inherit pkgs;
              inputs = inputs // {
                nix-configs = self;
              };
            };
          };
        in
        {
          config = {
            devenv = rendered.renderTarget "devenv";
            nixos = rendered.renderTarget "nixos";
            darwin = rendered.renderTarget "darwin";
            home = rendered.renderTarget "home";
            users = rendered.renderUsers;
          };
        };
      flake.nixosConfigurations = lib.pipe self.hostConfigurations [
        (lib.attrsets.filterAttrs (_: host: host.moduleType == "nixos"))
        (builtins.mapAttrs (
          _: host:
          lib.nixosSystem {
            inherit (host) system specialArgs;
            modules = host.modules ++ [
              (
                { kdnConfig, ... }:
                {
                  config.kdn.hostName = lib.mkDefault kdnConfig.hostName;
                }
              )
            ];
          }
        ))
      ];
      flake.darwinModules.default = ./modules/universal;
      flake.darwinConfigurations = lib.pipe self.hostConfigurations [
        (lib.attrsets.filterAttrs (_: host: host.moduleType == "darwin"))
        (builtins.mapAttrs (
          _: host:
          lib.darwinSystem {
            inherit (host) lib specialArgs;
            system = null;
            modules = host.modules ++ [
              { nixpkgs.system = host.system; }
              (
                { kdnConfig, ... }:
                {
                  config.kdn.hostName = lib.mkDefault kdnConfig.hostName;
                }
              )
            ];
          }
        ))
      ];

      flake.colmena =
        lib.infuse
          {
            meta.nixpkgs = import inputs.nixpkgs {
              system = "x86_64-linux";
              overlays = [ self.overlays.default ];
            };
            defaults.deployment.targetUser = "kdn";
          }
          (
            lib.attrsets.mapAttrsToList
              (
                name: module:
                let
                  host = self.hostConfigurations."${name}";
                in
                {
                  meta.nodeSpecialArgs."${name}".__init = host.specialArgs;
                  meta.nodeNixpkgs."${name}".__init = import inputs.nixpkgs {
                    inherit (host.specialArgs.kdnConfig) system;
                    overlays = [ self.overlays.default ];
                  };
                  "${name}".__init = {
                    imports = host.modules ++ [
                      module
                      (
                        { kdnConfig, ... }:
                        {
                          config.kdn.hostName = lib.mkDefault kdnConfig.hostName;
                        }
                      )
                    ];
                  };
                }
              )
              {
                etra.deployment.targetHost = "etra.lan.etra.net.int.kdn.im.";
                pwet.deployment.targetHost = "pwet.pic.etra.net.int.kdn.im.";
                turo.deployment.targetHost = "turo.pic.etra.net.int.kdn.im.";
                yost.deployment.targetHost = "yost.pic.etra.net.int.kdn.im.";
                moss.deployment.targetHost = "moss.kdn.im.";
              }
          );
      flake.colmenaHive = lib.colmena.makeHive self.colmena;
      flake.mkEasykubenix =
        system: modules:
        import inputs.easykubenix {
          inherit modules;
          pkgs = inputs.nixpkgs.legacyPackages.${system}.extend self.overlays.default;
          specialArgs =
            (self.kdnMetaModule.config.output.mkSubmodule { moduleType = "easykubenix"; }).specialArgs;
        };

      perSystem =
        {
          config,
          self',
          inputs',
          system,
          pkgs,
          ...
        }:
        {
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
          # Run a subset of the jj-experiments suite through a hermetic nix build.
          # It forwards any pytest flags:
          #   nix run '.#jj-experiments-run' -- -k placement -x
          # The args become a JSON array and drive checks/jj-experiments/subset-runner.nix.
          # The build is sandboxed and needs no `--impure`. No args runs the whole suite.
          apps.jj-experiments-run = {
            type = "app";
            program = lib.getExe (
              pkgs.writeShellApplication {
                name = "jj-experiments-run";
                runtimeInputs = with pkgs; [
                  nix-output-monitor
                  nix
                  jq
                  coreutils
                ];
                text = ''
                  root="''${JJX_REPO:-$PWD}"
                  if [ "$#" -eq 0 ]; then
                    json='[]'
                  else
                    json=$(printf '%s\n' "$@" | jq -R . | jq -sc .)
                  fi
                  exec nom build --file "$root/checks/jj-experiments/subset-runner.nix" \
                    --argstr repo "$root" --argstr extraArgsJSON "$json" --no-link -L
                '';
              }
            );
          };
          checks = pkgs.callPackages ./checks (
            self.kdnMetaModule.config.output.mkSubmodule {
              moduleType = "checks";
            }
          );
          devShells = { };
          packages = lib.mkMerge [
            (lib.filterAttrs (n: pkg: lib.isDerivation pkg)
              (flakeLib.overlayedInputs { inherit system; }).nixpkgs.kdn
            )
            # `nixosGenerate` builds a whole NixOS system, so every package in it needs a Linux
            # `hostPlatform`. On `aarch64-darwin` the evaluation stops at busybox: "Refusing to
            # evaluate package 'busybox-1.37.0' ... because it is not available on the requested
            # hostPlatform". `nix flake check` reads every entry of `packages.<system>`, so an
            # unguarded entry fails the whole check on a Darwin machine.
            (lib.optionalAttrs (lib.hasSuffix "-linux" system) {
              install-iso = inputs.nixos-generators.nixosGenerate {
                format = "install-iso";
                inherit system;
                inherit (self) lib;
                inherit (lib) nixosSystem;
                specialArgs = (self.kdnMetaModule.config.output.mkSubmodule { moduleType = "nixos"; }).specialArgs;
                modules = [ ./hosts/install-iso ];
              };
            })
            {
              sources =
                let
                  # A flake input graph holds cycles, because a `follows` can point back up the
                  # tree. So a walk of `input.inputs` must record every path it already took.
                  #
                  # The earlier walk did not. It recursed on `input.inputs` with no record, and it
                  # deduplicated only after the walk finished — too late to end one. Both
                  # `nix flake check` and `nix build .#sources` then failed with
                  # `stack overflow; max-call-depth exceeded`, on Darwin and on Linux.
                  #
                  # This walk goes one level at a time, and it drops a path it already holds. So it
                  # ends on any graph. It also keeps the **shallowest** name for each path, which is
                  # the choice the earlier `sort` by depth plus the dedupe made.
                  #
                  # `level` is a list of `{ name, input }`.
                  flattenInputs =
                    seen: level:
                    if level == [ ] then
                      [ ]
                    else
                      let
                        step =
                          lib.foldl'
                            (
                              acc: entry:
                              let
                                key = builtins.unsafeDiscardStringContext entry.input.outPath;
                              in
                              if acc.seen ? ${key} then
                                acc
                              else
                                {
                                  seen = acc.seen // {
                                    ${key} = true;
                                  };
                                  kept = acc.kept ++ [ entry ];
                                }
                            )
                            {
                              inherit seen;
                              kept = [ ];
                            }
                            level;

                        next = lib.concatMap (
                          entry:
                          lib.mapAttrsToList (name: input: {
                            name = "${entry.name}__${name}";
                            inherit input;
                          }) (entry.input.inputs or { })
                        ) step.kept;
                      in
                      map (entry: {
                        inherit (entry) name;
                        path = entry.input.outPath;
                      }) step.kept
                      ++ flattenInputs step.seen next;
                in
                lib.pipe inputs [
                  (lib.flip removeAttrs [ "self" ])
                  (lib.attrsets.filterAttrs (key: _: !(lib.strings.hasSuffix "-upstream" key)))
                  (lib.mapAttrsToList (name: input: { inherit name input; }))
                  (flattenInputs { })
                  (
                    l:
                    l
                    ++ [
                      {
                        name = ".self";
                        path = inputs.self.outPath;
                      }
                    ]
                  )
                  (pkgs.linkFarm "flake-inputs")
                ];
            }
          ];
        };
    });
}
