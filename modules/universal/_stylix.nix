{
  config,
  lib,
  pkgs,
  kdnConfig,
  ...
}:
let
  inherit (kdnConfig) inputs;
in
lib.optionalAttrs
  (kdnConfig.util.isOfType [
    "nixos"
    "home-manager"
    "darwin"
    "nix-on-droid"
  ])
  {
    imports =
      if kdnConfig.moduleType == "nixos" then
        [ inputs.stylix.nixosModules.stylix ]
      else if kdnConfig.moduleType == "darwin" then
        [ inputs.stylix.darwinModules.stylix ]
      else if kdnConfig.moduleType == "nix-on-droid" then
        [ inputs.stylix.nixOnDroidModules.stylix ]
      else if kdnConfig.moduleType == "home-manager" && kdnConfig.parent == null then
        [ inputs.stylix.homeModules.stylix ]
      else
        [ ];
    config = lib.mkMerge [
      {
        /*
          TODO: review new option added for simplifications?
           see https://github.com/danth/stylix/commit/7682713f6af1d32a33f8c4e3d3d141af5ad1761a
        */

        stylix.enable = true;
        /*
          stylix needs an image to evaluate, so this module keeps a neutral fallback.

          `data/stylix.nix` supplies the real wallpaper at `lib.mkDefault`, which is priority
          1000. This definition therefore needs a weaker priority. `lib.mkOptionDefault` is
          wrong: 1500 ties with the option's own `default`, and `stylix.image` is a `nullOr`
          type, so the tie raises `defined both null and not null`. 1250 sits strictly between
          1000 and 1500 and avoids both problems.
        */
        stylix.image = lib.mkOverride 1250 pkgs.nixos-artwork.wallpapers.simple-dark-gray.gnomeFilePath;
        stylix.polarity = lib.mkDefault "dark";
        stylix.base16Scheme = lib.mkDefault ./stylix.pallette.yaml;

        stylix.enableReleaseChecks = lib.mkDefault false;
      }
      (lib.attrsets.optionalAttrs (kdnConfig.parent == null) {
        stylix.fonts.monospace.name = lib.mkDefault "Fira Code";
        stylix.fonts.monospace.package = lib.mkDefault pkgs.fira-code;
      })
      (lib.attrsets.optionalAttrs
        (kdnConfig.util.isOfType [
          "nixos"
          "home-manager"
        ])
        {
          /*
            2026-09-09: a platform check is required, not only the module type check above. A
            home-manager child of a darwin host also has the "home-manager" type.

            stylix >=5e38098 sets `home.pointerCursor.<target>.enable` from its gtk, x11 and
            sway home-manager targets, and adds no platform guard there. `home.pointerCursor`
            works on Linux only, and its `name` option has no default. Any definition inside
            that submodule turns the home-manager module on, so the module then reads the
            missing `name` and the evaluation stops. A Linux-only cursor keeps `stylix.cursor`
            null on darwin, so those stylix targets stay inert.

            Two shapes are mandatory here:
            - `lib.mkIf`, not a condition on `optionalAttrs`. A condition on `optionalAttrs`
              forces `pkgs` while the module system still collects definitions, which gives an
              infinite recursion. `lib.mkIf` defers the test until the option merge.
            - one `mkIf` around the whole attrset, not one per key. `stylix.cursor` is a
              `nullOr submodule`, so a per-key `mkIf` still leaves the parent definition
              `{ }` in place and the cursor never becomes null.
          */
          stylix.cursor = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
            name = lib.mkDefault "phinger-cursors-${config.stylix.polarity}";
            package = lib.mkDefault pkgs.phinger-cursors;
            size = lib.mkDefault 32;
          };
        }
      )
      (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) (
        kdnConfig.util.ifTypes [ "home-manager" ] {
          # 2026-07-31: fixes a warning. home.pointerCursor is Linux-only, so enable it only for a
          # home-manager child of a nixos host, not on Darwin.
          home.pointerCursor.enable = lib.mkDefault true;
        }
      ))
      (kdnConfig.util.ifTypes [ "nixos" ] {
        fonts.fontDir.enable = true;
        # Follow `stylix.fonts.monospace`, so one override moves the installed font too. The
        # symbols package has no stylix option, so it stays a literal.
        fonts.packages = [
          config.stylix.fonts.monospace.package
          pkgs.fira-code-symbols
        ];
        stylix.enableReleaseChecks = lib.strings.versionAtLeast config.system.nixos.version "26.11";
      })
      (kdnConfig.util.ifTypes [ "home-manager" ] {
        stylix.enableReleaseChecks = lib.strings.versionAtLeast config.home.version.release "26.11";
      })
      # 2026-04-17 broken due to https://github.com/nix-community/stylix/issues/1686
      (kdnConfig.util.ifTypes [ "nixos" "home-manager" ] {
        stylix.targets.gtksourceview.enable = false;
      })
    ];
  }
