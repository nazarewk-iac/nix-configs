# The stylix theme of the old tree, as two den aspects.
#
# The old module stays in place and keeps working. This file is the parallel den implementation of
# `modules/universal/_stylix.nix`.
#
# ## Two names, one file
#
# | Name | Class | Subject |
# |---|---|---|
# | `stylix` | `nixos`, `darwin` | a whole machine |
# | `stylix-home` | `homeManager` | a **standalone** Home Manager, with no NixOS or Darwin parent |
#
# The split follows the old module. `_stylix.nix:26` imports the Home Manager stylix module only
# when `kdnConfig.parent == null`, because stylix's own `homeManagerIntegration` already pushes that
# module into every Home Manager user of a NixOS or a Darwin host.
#
# **Never include `stylix-home` on a nested user.** stylix's `copyModules` copies each `stylix.*`
# value from `osConfig` at `lib.mkDefault`, and the shared settings below write `lib.mkDefault` too.
# Two `mkDefault` definitions tie at priority 1000, and the evaluation then stops.
#
# ## What it does
#
# It turns stylix on, it picks the dark polarity, it loads the base16 palette next to this file, and
# it sets Fira Code as the monospace font. On NixOS it also installs the font and it turns the
# broken `gtksourceview` target off.
#
# ## What the port changes
#
# 1. **The module-type branch becomes a class key.** The old `imports` list reads
#    `kdnConfig.moduleType` and picks one of four stylix modules. Each den target imports its own
#    stylix module directly.
# 2. **The `nix-on-droid` branch goes.** den declares no `nixOnDroid` class, so that branch has no
#    counterpart. Add it when den gains the class.
# 3. **`kdnConfig.inputs` becomes the aspect file's own `inputs` argument.** Each target closes over
#    `inputs.stylix`, so no target takes a custom argument. That is the drop-in rule of ../README.md.
# 4. **The palette file is a copy.** An aspect reads no file of the deprecated tree, so
#    `./stylix.pallette.yaml` is a byte-exact copy of `modules/universal/stylix.pallette.yaml`. The
#    root `.gitignore` ignores a `.yaml` name, so that file needs its own allow line.
#
# ## The image fallback and its priority
#
# stylix needs an image to evaluate, so the shared settings keep a neutral fallback from nixpkgs.
# The priority is `lib.mkOverride 1250`, and no other value works:
#
# - A real wallpaper arrives at `lib.mkDefault`, which is priority 1000. So the fallback must be
#   weaker than 1000.
# - `lib.mkOptionDefault` is 1500, and it ties with the option's own `default`. `stylix.image` is a
#   `nullOr` type, so the tie raises `defined both null and not null`.
#
# 1250 sits strictly between the two and avoids both problems.
#
# ## The cursor block and its two mandatory shapes
#
# Both the `nixos` target and the `homeManager` target set `stylix.cursor`, and both guard it on the
# platform. The guard is not optional, and neither is its shape. Measured 2026-09-09 on the old
# module, and repeated here on 2026-09-11:
#
# - `lib.mkIf`, never a condition on `lib.optionalAttrs`. A condition on `optionalAttrs` forces
#   `pkgs` while the module system still collects definitions, which gives an infinite recursion.
#   `lib.mkIf` defers the test until the option merge.
# - one `mkIf` around the whole attribute set, never one per key. `stylix.cursor` is a
#   `nullOr submodule`, so a per-key `mkIf` still leaves the parent definition `{ }` in place and the
#   cursor never becomes null.
#
# Why the guard exists: stylix sets `home.pointerCursor.<target>.enable` from its gtk, x11 and sway
# Home Manager targets, and it adds no platform guard there. `home.pointerCursor` works on Linux
# only, and its `name` option has no default. Any definition inside that submodule turns the module
# on, so the module then reads the missing `name` and the evaluation stops.
#
# ## One old line that a consumer keeps
#
# `_stylix.nix:89-95` writes `home.pointerCursor.enable = lib.mkDefault true` for a Home Manager
# child of a NixOS host. This file writes that line in the `homeManager` target, under the same
# Linux guard. A **nested** user reaches no `homeManager` target here, so a NixOS host that runs
# Home Manager adds the line itself:
#
#     home-manager.sharedModules = [ { home.pointerCursor.enable = lib.mkDefault true; } ];
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. Neither aspect declares an option.
# 3. **No custom module argument.** Every target module below takes `config`, `lib` and `pkgs` only.
{ inputs, ... }:
let
  # Every value the old module sets for all four module types, in one place. Each target imports it
  # by path, so the module system dedupes it.
  settings =
    { lib, pkgs, ... }:
    {
      stylix.enable = true;

      # See the "image fallback" section above. 1250 is the only correct priority here.
      stylix.image = lib.mkOverride 1250 pkgs.nixos-artwork.wallpapers.simple-dark-gray.gnomeFilePath;

      stylix.polarity = lib.mkDefault "dark";
      stylix.base16Scheme = lib.mkDefault ./stylix.pallette.yaml;
      stylix.enableReleaseChecks = lib.mkDefault false;

      # The old module sets the font only when `kdnConfig.parent == null`. Every target of this file
      # is such a top-level subject, so the font belongs in the shared settings.
      stylix.fonts.monospace.name = lib.mkDefault "Fira Code";
      stylix.fonts.monospace.package = lib.mkDefault pkgs.fira-code;
    };

  # See the "cursor block" section above for the two mandatory shapes.
  cursor =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      stylix.cursor = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        name = lib.mkDefault "phinger-cursors-${config.stylix.polarity}";
        package = lib.mkDefault pkgs.phinger-cursors;
        size = lib.mkDefault 32;
      };
    };

  nixosTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        inputs.stylix.nixosModules.stylix
        settings
        cursor
      ];

      fonts.fontDir.enable = true;
      # Follow `stylix.fonts.monospace`, so one override moves the installed font too. The symbols
      # package has no stylix option, so it stays a literal.
      fonts.packages = [
        config.stylix.fonts.monospace.package
        pkgs.fira-code-symbols
      ];

      stylix.enableReleaseChecks = lib.strings.versionAtLeast config.system.nixos.version "26.11";

      # 2026-04-17 broken, see https://github.com/nix-community/stylix/issues/1686
      stylix.targets.gtksourceview.enable = false;
    };

  darwinTarget = {
    imports = [
      inputs.stylix.darwinModules.stylix
      settings
    ];
  };

  homeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        inputs.stylix.homeModules.stylix
        settings
        cursor
      ];

      stylix.enableReleaseChecks = lib.strings.versionAtLeast config.home.version.release "26.11";

      # 2026-04-17 broken, see https://github.com/nix-community/stylix/issues/1686
      stylix.targets.gtksourceview.enable = false;

      # `home.pointerCursor` works on Linux only, and its `name` option has no default. The `cursor`
      # module above supplies the name under the same Linux guard.
      home.pointerCursor.enable = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (lib.mkDefault true);
    };
in
{
  kdn.stylix.nixos = nixosTarget;
  kdn.stylix.darwin = darwinTarget;

  kdn.stylix-home.homeManager = homeTarget;
}
