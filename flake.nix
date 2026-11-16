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
  inputs.brew.url = "github:Homebrew/brew/7.0.11";
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
  inputs.nix-rosetta-builder.url = "github:nazarewk/nix-rosetta-builder/feat/in-place-updates";
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
  # The build-farm proxy project. The `build-farm` aspect currently renders HAProxy directly (its
  # `balance first` is not in yensid's strategy enum), but the away-mode design and the per-builder
  # `ca` host-key module come from here, so the input is kept to migrate back onto its modules.
  inputs.yensid.url = "github:garnix-io/yensid";
  inputs.yensid.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nur.url = "github:nix-community/NUR";
  inputs.oh-my-pi.url = "github:can1357/oh-my-pi";
  # Upstream Pi as a flake: npm/Bun packages, NixOS + Home Manager modules, and an
  # overlay providing pkgs.pi-coding-agent. It tracks upstream releases (newer than the
  # nixpkgs pin) and follows our nixpkgs so it builds against our pin.
  inputs.pi.url = "github:lukasl-dev/pi.nix";
  # Reuse this repo's shared pins instead of dragging duplicates. `nixpkgs-x86_64-darwin`
  # is deliberately NOT followed: pi.nix pins it for the legacy Intel-macOS branch.
  inputs.pi.inputs.nixpkgs.follows = "nixpkgs";
  inputs.pi.inputs.flake-parts.follows = "flake-parts";
  inputs.pi.inputs.bun2nix.inputs.flake-parts.follows = "flake-parts";
  inputs.pi.inputs.bun2nix.inputs.systems.follows = "systems";
  inputs.pi.inputs.bun2nix.inputs.treefmt-nix.follows = "treefmt-nix";
  # OpenCode DSML compat-proxy. The nazarewk-iac fork's `main` aggregates the
  # patches this repo used to apply (Authorization forwarding, per-model routing,
  # streaming usage). Upstream has no flake.nix, so this is a plain source input.
  inputs.opencode-compat-proxy.flake = false;
  inputs.opencode-compat-proxy.url = "github:nazarewk-iac/opencode_compat_proxy";
  inputs.pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
  inputs.pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";
  inputs.uv2nix.url = "github:pyproject-nix/uv2nix";
  inputs.preservation-upstream.flake = false; # no need for upstream to be a flake
  inputs.preservation-upstream.url = "github:nix-community/preservation";
  inputs.preservation.url = "github:nazarewk-iac/preservation/nix-configs";
  # The nazarewk-iac fork carries the native `rosec-sops` provider: a Secret Service daemon whose
  # store is a sops-encrypted file tree. It is a flake with one package output (`packages.<system>.rosec`),
  # so the module takes the package from the input instead of the user profile.
  inputs.rosec.url = "github:nazarewk-iac/rosec";
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
  inputs.rosec.inputs.nixpkgs.follows = "nixpkgs";
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

  # Found by `hack/flake-structure-analysis.py`: transitive inputs that pinned their own
  # source. Keep this list in sync with that script.
  inputs.devenv.inputs.flake-compat.follows = "flake-compat";
  inputs.devenv.inputs.flake-parts.follows = "flake-parts";
  inputs.devenv.inputs.nixd.inputs.treefmt-nix.follows = "treefmt-nix";
  inputs.devenv.inputs.rust-overlay.follows = "rust-overlay";
  inputs.flake-utils.inputs.systems.follows = "systems";
  inputs.nix-homebrew.inputs.brew-src.follows = "brew";
  inputs.nixos-anywhere.inputs.nixos-stable.follows = "nixpkgs-stable";
  inputs.oh-my-pi.inputs.bun2nix-darwin-x64.inputs.flake-parts.follows = "flake-parts";
  inputs.oh-my-pi.inputs.bun2nix-darwin-x64.inputs.treefmt-nix.follows = "treefmt-nix";
  inputs.oh-my-pi.inputs.bun2nix.inputs.flake-parts.follows = "flake-parts";
  inputs.oh-my-pi.inputs.bun2nix.inputs.treefmt-nix.follows = "treefmt-nix";
  inputs.oh-my-pi.inputs.crane.follows = "crane";
  inputs.oh-my-pi.inputs.nixpkgs-darwin-x64.follows = "nixpkgs";
  inputs.pi.inputs.bun2nix-x86_64-darwin.inputs.treefmt-nix.follows = "treefmt-nix";
  inputs.pi.inputs.nixpkgs-x86_64-darwin.follows = "nixpkgs";
  inputs.stylix.inputs.base16.follows = "base16";
  inputs.yensid.inputs.agenix.inputs.home-manager.follows = "home-manager";
  inputs.yensid.inputs.agenix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.yensid.inputs.agenix.inputs.systems.follows = "systems";
  inputs.yensid.inputs.garnix-lib.inputs.nixpkgs.follows = "nixpkgs";
  inputs.yensid.inputs.nixos-compose.inputs.flake-utils.follows = "flake-utils";
  inputs.yensid.inputs.nixos-compose.inputs.flake-utils.inputs.systems.follows = "systems";
  inputs.yensid.inputs.nixos-compose.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    inputs@{
      flake-parts,
      self,
      ...
    }:
    let
      inherit (self) lib;

      flakeLib = lib.kdn.flakes.forFlake self;

      # One evaluated pkgs per (system, variant), shared by every host of that system. Producer:
      # modules/den-pkgs. A host opts in by setting nixpkgs.pkgs to self.pkgs.<system>.<variant>.
      supportedSystems = builtins.filter (system: system != "x86_64-darwin") (import inputs.systems);
      denPkgsLib = import ./modules/den-pkgs { inherit inputs self; };
    in
    (flake-parts.lib.mkFlake { inherit inputs; } {
      # `inputs.systems` is `nix-systems/default`, which still lists `x86_64-darwin`. Nixpkgs
      # 26.11 dropped that platform, and every evaluation of it throws "Nixpkgs 26.11 has dropped
      # support for x86_64-darwin". `nix flake check --all-systems` reads each system, so the
      # throw stops the whole check. Measured 2026-09-10. Every Darwin host here is
      # `aarch64-darwin`, so the platform has no use.
      systems = builtins.filter (system: system != "x86_64-darwin") (import inputs.systems);

      # The parallel den tree. It adds outputs and it changes none. See modules/den/README.md.
      imports = [
        # A standalone home-manager output (see `flake.homeConfigurations.dummy`). flake-parts does
        # not know `homeConfigurations`, so declare it as a lazy attrset.
        ({ lib, ... }: {
          options.flake.homeConfigurations = lib.mkOption {
            type = lib.types.lazyAttrsOf lib.types.raw;
            default = { };
            description = "Standalone home-manager configurations (no NixOS host).";
          };
        })
        ./modules/den/flake-module.nix
        # `nix fmt` and the check: one formatter for Markdown (and room for more). Nix stays with
        # `kdn-nix-fmt`; see treefmt.nix for why.
        inputs.treefmt-nix.flakeModule
      ];

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
        # `typescript-language-server` 6.0.2 ships a stale `pnpmDeps` hash. The pinned `pnpm_12`
        # produces a different tarball than the hash records, so the FOD fails on every build. The
        # fetched output is healthy, so the tree records the real hash here. Remove this entry when
        # upstream corrects the package.
        (final: prev: {
          typescript-language-server = prev.typescript-language-server.overrideAttrs (old: {
            pnpmDeps = old.pnpmDeps.overrideAttrs (_: {
              outputHash = "sha256-klxImN6Bp5/t6V0LfsmYNBvSzYq9Qz9dIU2mkvScx5k=";
            });
          });
        })
        # `scooter` 0.10.0 now depends on `onig_sys`, whose build script needs `pkg-config` +
        # `oniguruma`, which the package does not declare. Add them until nixpkgs does.
        (final: prev: {
          scooter = prev.scooter.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.pkg-config ];
            buildInputs = (old.buildInputs or [ ]) ++ [ prev.oniguruma ];
          });
        })
        # `angle-grinder` 0.19.6's vendored `tikv-jemalloc-sys` build script panics because it gets
        # `JEMALLOC_OVERRIDE=nixpkgs.<LIB>` — not a real path after the newer rust toolchain. Drop
        # the override so it builds its own jemalloc. No upstream fix yet; remove when nixpkgs does.
        (final: prev: {
          # `tikv-jemalloc-sys` needs a jemalloc built with its `_rjem_` symbol prefix, which the
          # system jemalloc is not. The nixpkgs cargo hook always sets JEMALLOC_OVERRIDE to a
          # sentinel, so the crate never builds its own. Unset it in preBuild so the vendored
          # build produces its own prefixed jemalloc (same as upstream's intent).
          angle-grinder = prev.angle-grinder.overrideAttrs (old: {
            preBuild = (old.preBuild or "") + "\nunset JEMALLOC_OVERRIDE\n";
          });
        })
        # `atuin` 18.23.0 fails its darwin e2e tests (`e2e_capture` and `e2e_pty`). That is
        # nixpkgs issue #573527. The tests drive an interactive bash in a pty, and they time out
        # on darwin. Skip the checks on darwin. Remove this entry when the package passes its
        # tests on darwin again.
        (
          final: prev:
          prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
            atuin = prev.atuin.overrideAttrs (_: {
              doCheck = false;
            });
          }
        )
      ];

      # The host-independent overlays from `modules/den-pkgs/overlays.nix`. A pinned host bakes them
      # into its single pkgs instance through `self.overlays.default`; the unpinned pkgs that den
      # targets and the devshell receive must carry the same set, or one package (nickel today) is
      # built twice with different inputs and the profile holds both derivations.
      flake.overlays.static = inputs.nixpkgs.lib.composeManyExtensions (
        import ./modules/den-pkgs/overlays.nix {
          lib = inputs.nixpkgs.lib;
          inherit inputs;
        }
      );

      flake.overlays.default = inputs.nixpkgs.lib.composeManyExtensions [
        self.overlays.packages
        self.overlays.static
        inputs.nur.overlays.default
        inputs.microvm.overlays.default
        inputs.angrr.overlays.default
        inputs.nix-darwin.overlays.default
        inputs.devenv.overlays.default
        inputs.oh-my-pi.overlays.default # provides pkgs.omp
        # Choose pi-coding-agent across three sources: a local copy in this repo
        # (packages/pi-coding-agent), the upstream pi.nix flake, and nixpkgs.
        #
        # The local copy wins only if it is at least as new as the newest upstream, or if
        # it carries patches (a `packages/pi-coding-agent/PATCHED` file). Otherwise the
        # newest upstream wins, so a stale local copy does not shadow a newer release.
        (
          final: prev:
          let
            sys = final.stdenv.hostPlatform.system;
            versionOf = p: p.version or (p.meta.version or "0");

            repoDir = ./packages/pi-coding-agent;
            repo = if builtins.pathExists repoDir then prev.callPackage repoDir { } else null;
            # A derivation does not expose `.patches`, so a local copy signals patches the
            # idiomatic way: `passthru.patches` (non-empty) or `passthru.patched = true`.
            # A `packages/pi-coding-agent/PATCHED` file also works as a last resort.
            #
            # Do not try to read `repo.drvPath` here. That is import-from-derivation, which a pure
            # flake evaluation refuses ("access to absolute path ... is forbidden in pure eval
            # mode"), and `nixos-rebuild` evaluates purely. The three markers above are enough.
            repoPatches = if repo == null then [ ] else (repo.passthru.patches or (repo.patches or [ ]));
            repoPatched =
              repo != null
              && (
                (repo.passthru.patched or false) || repoPatches != [ ] || builtins.pathExists (repoDir + "/PATCHED")
              );
            repoVer = if repo != null then versionOf repo else "0";

            upstream = (inputs.pi.packages.${sys} or { }).coding-agent or prev.pi-coding-agent;
            upstreamVer = versionOf upstream;
            nixpkgsVer = versionOf prev.pi-coding-agent;

            upstreamIsNewer = final.lib.versionAtLeast upstreamVer nixpkgsVer;
            best = if upstreamIsNewer then upstream else prev.pi-coding-agent;
            bestVer = if upstreamIsNewer then upstreamVer else nixpkgsVer;
          in
          {
            pi-coding-agent =
              if repo != null && (repoPatched || final.lib.versionAtLeast repoVer bestVer) then repo else best;
          }
        )
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
      # `<flake>.pkgs.<system>.{default,cuda}` — the pinned sets. See modules/den-pkgs.
      flake.pkgs = lib.genAttrs supportedSystems (system: denPkgsLib.forSystem system);

      # A "dummy" standalone home-manager profile: how an adopter configures HM WITHOUT a NixOS/
      # nix-darwin host, on the same single pinned pkgs. It builds against the pinned base, so it
      # carries the repo overlays (kdn packages) with no extra nixpkgs instantiation.
      flake.homeConfigurations.dummy = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = self.pkgs.x86_64-linux.default;
        modules = [
          ({ ... }: {
            home.username = "dummy";
            home.homeDirectory = "/home/dummy";
            home.stateVersion = "26.05";
            programs.git.enable = true;
          })
        ];
      };
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

          # The formatter for every language, defined in ./treefmt.nix. `nix fmt` runs it; the same
          # module adds `checks.<system>.treefmt` so `nix flake check` fails on unformatted files.
          treefmt.config = import ./treefmt.nix { };
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
          # Run every OKF gate on the memory bundle in the working tree. The checks run the same
          # gates on a sandbox copy; this is the authoring loop. Pass a bundle path to check
          # another one: `nix run .#okf-check -- path/to/bundle`.
          apps.okf-check = {
            type = "app";
            program = lib.getExe (
              pkgs.writeShellApplication {
                name = "okf-check";
                runtimeInputs = [
                  pkgs.kdn.kdn-okf
                  pkgs.kdn.okf-agent-memory
                  pkgs.kdn.ai-xf
                  pkgs.kdn.okf-rs
                  pkgs.kdn.okflint
                  pkgs.kdn.okph
                ];
                text = builtins.readFile ./hack/okf-check.sh;
              }
            );
          };
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
          # The macOS-guest activation gate. It is NOT a check and it joins NO bundle: a bundle
          # member is a derivation, and the Nix sandbox grants no Hypervisor entitlement, no network
          # and no writable disk image. `bundle-vm` therefore stays empty for ever — see
          # ./checks/bundles.nix and docs/tasks/2026-09/darwin-vm-testing/design.md.
          #
          # Run it by hand, never per edit. `bake` costs 40 to 60 min once; `run` costs 5 to 15 min.
          #
          #   nix run '.#darwin-vm-test' -- bake
          #   nix run '.#darwin-vm-test' -- run
          #
          # It needs no host `sudo` — Apple Virtualization runs unprivileged — and it deletes only a
          # guest it made itself, under the `kdn-vmtest-clone-` prefix. `tart` comes from Homebrew,
          # because the nixpkgs package is stale at 2.30.6 and marked unfree.
          #
          # The app carries NO evaluation-time platform guard, for two measured reasons. A second
          # `apps = lib.optionalAttrs ... ` in this attribute set is a duplicate-attribute error,
          # because the lines above already define `apps.<name>`. Moving the guard into `imports`
          # then reads `pkgs` from `_module.args`, and the module system answers that with
          # `error: infinite recursion encountered`. The script guards itself instead: it looks for
          # `tart` and exits with an install hint when it finds none. `tart` is macOS-only.
          apps.darwin-vm-test = {
            type = "app";
            program = lib.getExe (
              pkgs.writeShellApplication {
                name = "darwin-vm-test";
                runtimeInputs = with pkgs; [
                  coreutils
                  curl
                  gnugrep
                  nix
                ];
                text = builtins.readFile ./hack/darwin-vm-test.sh;
              }
            );
          };
          # The bundles ride on the assembled check set, so they attach here and not in
          # ./checks/default.nix. ./checks/README.md holds the measured time of each bundle.
          checks =
            let
              base = pkgs.callPackages ./checks (
                self.kdnMetaModule.config.output.mkSubmodule {
                  moduleType = "checks";
                }
              );
            in
            base
            // import ./checks/bundles.nix {
              inherit pkgs lib;
              checks = base;
            };
          devShells = { };
          packages = lib.mkMerge [
            # The generated treefmt.toml, so `devenv.nix` can symlink it into the repository. `jj fix`
            # then calls `treefmt --stdin`, governed by that one file, instead of repeating a
            # per-tool list. `config.treefmt.build.configFile` and `.wrapper` are the treefmt-nix
            # outputs.
            {
              treefmt-config = config.treefmt.build.configFile;
              # The wrapper is `treefmt --config-file <treefmt-config>`; `jj fix` runs it with
              # `--stdin`, so the two packages go together.
              treefmt-wrapper = config.treefmt.build.wrapper;
            }
            # The version-selected Pi (local copy > pi.nix > nixpkgs). Exposed as a flake package
            # so a consumer whose pkgs has no repo overlay — the devenv shell — still gets 1.4.0
            # instead of nixpkgs' older pin.
            {
              pi-coding-agent = (flakeLib.overlayedInputs { inherit system; }).nixpkgs.pi-coding-agent;
            }
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
