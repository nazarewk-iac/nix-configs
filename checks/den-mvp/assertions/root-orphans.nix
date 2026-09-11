# Tier-1 assertions for the three aspects that come from the root of the old universal tree.
#
# Every assertion is `{ name; expected; actual; }`, and `mkEvalCheck` compares the two at evaluation
# time. Nothing here builds a system and nothing activates.
#
# ## The subjects
#
# | Subject | Class | What it states |
# |---|---|---|
# | `stylixNixos` | `nixos` | the `stylix` aspect on a bare NixOS, no consumer opinion |
# | `stylixDarwin` | `darwin` | the `stylix` aspect on a bare nix-darwin |
# | `stylixHome` | `homeManager` | the `stylix-home` aspect on a **standalone** Home Manager |
# | `bootstrapHome` | `homeManager` | the `hm-bootstrap` aspect alone |
#
# ## Two platform facts the assertions below depend on
#
# 1. **The bare Home Manager and the bare nix-darwin harness both run `aarch64-darwin`.** So every
#    Linux-only value stays at its off state here. `stylix.cursor` is null in the Home Manager
#    subject, and `home.pointerCursor.enable` stays `false`. The Linux branch gets its coverage from
#    the NixOS subject, which runs `x86_64-linux`.
# 2. **The nix-darwin stylix module declares no `stylix.cursor` option at all.** Measured 2026-09-11:
#    a read of `config.stylix.cursor` in the darwin subject raises `attribute 'cursor' missing`. So
#    the assertion tests the presence of the option, not its value.
#
# ## One option with an `apply` function
#
# `systemd.user.startServices` cannot be read back as the string the aspect writes. Its declaration
# in `<home-manager>/modules/systemd.nix:335-343` carries
# `apply = p: if isBool p then p else p == "sd-switch"`, so `"suggest"` becomes `false`. The
# assertion therefore expects `false`, and that is the correct proof that `"suggest"` arrived.
{
  lib,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos bareDarwinSystem bareHomeConfiguration;

  sorted = lib.sort (a: b: a < b);

  orphanNames = [
    "hm-bootstrap"
    "stylix"
    "stylix-home"
  ];

  stylixNixosSystem = bareNixos (
    denLib.imports {
      class = "nixos";
      aspects = [ "stylix" ];
    }
  );
  stylixNixos = stylixNixosSystem.config;

  stylixDarwinSystem = bareDarwinSystem (
    denLib.imports {
      class = "darwin";
      aspects = [ "stylix" ];
    }
  );
  stylixDarwin = stylixDarwinSystem.config;

  stylixHomeConfiguration = bareHomeConfiguration (
    denLib.imports {
      class = "homeManager";
      aspects = [ "stylix-home" ];
    }
  );
  stylixHome = stylixHomeConfiguration.config;

  bootstrapHomeConfiguration = bareHomeConfiguration (
    denLib.imports {
      class = "homeManager";
      aspects = [ "hm-bootstrap" ];
    }
  );
  bootstrapHome = bootstrapHomeConfiguration.config;

  # A local copy on purpose. A shared helper file under ./ breaks the area scan of ./default.nix.
  has = name: packages: lib.elem name (map lib.getName packages);
in
{
  assertions = [
    # ---------------------------------------------------------------- instantiation
    {
      name = "the root-orphan aspects instantiate in all three classes";
      expected = {
        nixos = true;
        darwin = true;
        home = true;
        bootstrap = true;
      };
      actual = {
        nixos = builtins.isString stylixNixos.system.build.toplevel.drvPath;
        darwin = builtins.isString stylixDarwin.system.build.toplevel.drvPath;
        home = builtins.isString stylixHome.home.activationPackage.drvPath;
        bootstrap = builtins.isString bootstrapHome.home.activationPackage.drvPath;
      };
    }
    {
      name = "each root-orphan aspect emits the classes its old module had";
      expected = {
        hm-bootstrap = [ "homeManager" ];
        stylix = [
          "darwin"
          "nixos"
        ];
        stylix-home = [ "homeManager" ];
      };
      actual = lib.mapAttrs (_: sorted) (lib.getAttrs orphanNames denLib.pairs);
    }

    # ---------------------------------------------------------------- stylix, shared settings
    {
      name = "stylix turns on in every class";
      expected = {
        nixos = true;
        darwin = true;
        home = true;
      };
      actual = {
        nixos = stylixNixos.stylix.enable;
        darwin = stylixDarwin.stylix.enable;
        home = stylixHome.stylix.enable;
      };
    }
    {
      name = "the base16 palette comes from the file next to the aspect";
      expected = "stylix.pallette.yaml";
      actual = builtins.baseNameOf (toString stylixNixos.stylix.base16Scheme);
    }
    {
      name = "the polarity is dark";
      expected = "dark";
      actual = stylixNixos.stylix.polarity;
    }
    {
      name = "the image fallback keeps stylix evaluable with no wallpaper";
      expected = false;
      actual = stylixNixos.stylix.image == null;
    }
    {
      name = "the monospace font is Fira Code in every class";
      expected = {
        nixos = "Fira Code";
        darwin = "Fira Code";
        home = "Fira Code";
      };
      actual = {
        nixos = stylixNixos.stylix.fonts.monospace.name;
        darwin = stylixDarwin.stylix.fonts.monospace.name;
        home = stylixHome.stylix.fonts.monospace.name;
      };
    }

    # ---------------------------------------------------------------- stylix, per class
    {
      name = "the NixOS class installs the monospace font and its symbols";
      expected = {
        fontDir = true;
        fira = true;
        symbols = true;
      };
      actual = {
        fontDir = stylixNixos.fonts.fontDir.enable;
        fira = has "fira-code" stylixNixos.fonts.packages;
        symbols = has "fira-code-symbols" stylixNixos.fonts.packages;
      };
    }
    {
      name = "the release check follows the version of the class that carries it";
      expected = {
        nixos = true;
        darwin = false;
        home = true;
      };
      actual = {
        nixos = stylixNixos.stylix.enableReleaseChecks;
        darwin = stylixDarwin.stylix.enableReleaseChecks;
        home = stylixHome.stylix.enableReleaseChecks;
      };
    }
    {
      name = "the broken gtksourceview target stays off";
      expected = {
        nixos = false;
        home = false;
      };
      actual = {
        nixos = stylixNixos.stylix.targets.gtksourceview.enable;
        home = stylixHome.stylix.targets.gtksourceview.enable;
      };
    }
    {
      name = "the cursor reaches Linux only";
      expected = {
        nixosName = "phinger-cursors-dark";
        nixosSize = 32;
        darwinHasOption = false;
        homeCursorNull = true;
        homePointerCursor = false;
      };
      actual = {
        nixosName = stylixNixos.stylix.cursor.name;
        nixosSize = stylixNixos.stylix.cursor.size;
        darwinHasOption = stylixDarwin.stylix ? cursor;
        homeCursorNull = stylixHome.stylix.cursor == null;
        homePointerCursor = stylixHome.home.pointerCursor.enable;
      };
    }

    # ---------------------------------------------------------------- hm-bootstrap
    {
      name = "the bootstrap aspect turns XDG on and only suggests a service restart";
      expected = {
        xdg = true;
        startServices = false;
      };
      actual = {
        xdg = bootstrapHome.xdg.enable;
        startServices = bootstrapHome.systemd.user.startServices;
      };
    }
  ];

  instantiatedBy = {
    hm-bootstrap = "den-eval-root-orphans (bare home)";
    stylix = "den-eval-root-orphans (bare nixos, bare darwin)";
    stylix-home = "den-eval-root-orphans (bare home, standalone)";
  };
}
