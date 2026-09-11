# The `development/nix` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It gives one user the Nix language tools: two language servers, three formatters,
# `nixos-anywhere`, and `nh` with a default flake path baked in.
#
# It is a Home Manager opinion only. The old module puts every package behind `ifNotHMParent`, and
# the helix settings behind `ifHM`, so a host writes nothing of its own.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`nh.enable` becomes `nh.use`.** A reachable `enable` option is forbidden. The name changes;
#    the meaning and the `true` default do not.
# 3. **`kdn.env.packages` goes.** The target writes `home.packages` through
#    ../common/filter-packages.nix. Design B.
# 4. **The old `kdn.toolset.nix.enable` write goes.** A host states that aspect itself. The old
#    line is `lib.mkDefault true`, so a machine that wants it names `toolset` in its own list.
# 5. **`kdn-nix-fmt` comes from a plain `callPackage`.** The old module reads the `kdn` package
#    set, so a consumer must add this repository's overlay first. A relative path needs no overlay.
# 6. **`overridablePackageType` is inlined.** The old module calls a helper of this repository's
#    `lib`, and an aspect reaches no such helper. The four sub-options and the fold order stay
#    exactly the same.
#
# ## No personal path in this file
#
# `kdn.dev-nix.flake.path` defaults to `null`, and this file names no checkout of its own. A
# consumer states the path of its own flake checkout. That matches the old module, which already
# takes the value from a data folder outside the module tree.
#
# A `lib.mkOptionDefault` cannot neutralise the default, because the type is `nullOr`: an option's
# own `default` sits at priority 1500 and `mkOptionDefault` is also 1500. Use `lib.mkOverride 1400`
# when a consumer must un-set a value another module states.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 2 above.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.dev-nix.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.dev-nix;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      # The root of this repository, as a relative path. `kdn-nix-fmt` is a Python script package,
      # and it builds its wrapper with `lib.kdn.mkPythonScript` unless a caller states this root.
      # A plain `callPackage` with no root therefore needs this repository's `lib` extension. The
      # root closes that gap and keeps the overlay-free route.
      repoRoot = ../../..;

      kdn-nix-fmt = pkgs.callPackage ../../../packages/kdn-nix-fmt {
        __inputs__.inputs.kdn-configs-src = repoRoot;
      };

      # The `overridablePackageType` helper of this repository's `lib`, inlined. An aspect reaches
      # no repository helper, so the type lives here. `final` applies every `overrides` function
      # first and every `overrideAttrs` function second, in list order.
      overridablePackageType =
        pkg:
        lib.types.submodule (args: {
          options.prev = lib.mkOption {
            type = lib.types.package;
            default = pkg;
            description = "The package before any override runs.";
          };
          options.overrides = lib.mkOption {
            type = with lib.types; listOf (functionTo (attrsOf anything));
            default = [ ];
            description = "Functions this tree folds into one `override` call, in order.";
          };
          options.overrideAttrs = lib.mkOption {
            type = with lib.types; listOf (functionTo (attrsOf anything));
            default = [ ];
            description = "Functions this tree folds into one `overrideAttrs` call, in order.";
          };
          options.final = lib.mkOption {
            type = lib.types.package;
            default = lib.pipe args.config.prev [
              (p: p.override (prev: lib.lists.foldl (old: fn: fn old) prev args.config.overrides))
              (p: p.overrideAttrs (prev: lib.lists.foldl (old: fn: fn old) prev args.config.overrideAttrs))
            ];
            defaultText = lib.literalExpression "config.prev with every override applied";
            description = "The package this user installs.";
          };
        });
    in
    {
      options.kdn.dev-nix.nh.use = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Install `nh`, the Nix helper.

          The old module names this option `nh.enable`. A den aspect declares no reachable `enable`
          option, so the name changes and the meaning stays.
        '';
      };

      options.kdn.dev-nix.nh.flake = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = cfg.flake.path;
        defaultText = lib.literalExpression "config.kdn.dev-nix.flake.path";
        description = ''
          The value `nh` gets as its default `NH_FLAKE`.

          `null` means the wrapper sets no default at all.
        '';
      };

      options.kdn.dev-nix.nh.package = lib.mkOption {
        type = overridablePackageType pkgs.nh;
        default = { };
        description = "The `nh` package, and the override lists this aspect folds into it.";
      };

      options.kdn.dev-nix.flake.path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/etc/nixos";
        description = ''
          Path of the flake checkout this machine rebuilds from.

          `null` means the machine names no checkout. Then `nh.flake` carries no value and the
          wrapper sets no default `NH_FLAKE`.

          This aspect names no checkout of its own. A consumer states the path, or keeps `null`.

          A `lib.mkOptionDefault` cannot neutralise this default, because the type is `nullOr`. Use
          `lib.mkOverride 1400` when a consumer must un-set it.
        '';
      };

      config = lib.mkMerge [
        {
          programs.helix.extraPackages = with pkgs; [
            nil
            nixd
          ];
          programs.helix.languages.language = [
            {
              name = "nix";
              auto-format = true;
              formatter = {
                command = lib.getExe kdn-nix-fmt;
              };
            }
          ];

          home.packages = filterPackages (
            (with pkgs; [
              nixos-anywhere

              # language servers
              nil
              nixd

              # formatters
              alejandra
              nixfmt # used to be nixfmt-rfc-style
            ])
            ++ [ kdn-nix-fmt ]
          );
        }
        (lib.mkIf cfg.nh.use {
          home.packages = filterPackages [ cfg.nh.package.final ];

          kdn.dev-nix.nh.package.overrideAttrs = lib.lists.optional (cfg.nh.flake != null) (prev: {
            buildCommand = lib.strings.replaceString "$out/bin/nh" (
              "$out/bin/nh "
              + lib.strings.escapeShellArgs [
                "--set-default"
                "NH_FLAKE"
                cfg.nh.flake
              ]
            ) prev.buildCommand;
          });
        })
      ];
    };
}
