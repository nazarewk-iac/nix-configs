# The per-application registry, as a den aspect. It ports `modules/universal/apps/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It gives one name to every graphical or interactive application a user runs. Each entry holds
# three things:
#
#   - a switch, so a profile turns the application on or off by name
#   - a package, plus a list of overlay functions that patch that package
#   - the directories and the files the application keeps between boots
#
# 34 files of the old tree name `kdn.apps.*`, and 9 of them read a final package back out. That is
# the widest single leaf of the machine layer, so it ports early.
#
# ## Why the `homeManager` class alone
#
# The old module declares the option tree in every context, and every real effect it emits sits
# behind a Home Manager guard: `ifNotHMParent` installs the packages, `ifHM` records the
# directories. The host half exists only to forward the value into `home-manager.sharedModules`,
# and den needs no forward — den partitions an aspect by scope, so a user aspect reaches the user's
# own Home Manager config directly.
#
# So a den host reaches this aspect through a **user**, never through the host aspect.
#
# ## What the port changes
#
# 1. **`kdn.env.packages` does not survive.** A den target names its class, so this one writes
#    `home.packages` directly. The `apply` filter of the old option moves to
#    ../common/filter-packages.nix, and the call below opts in per list.
# 2. **The persistence write becomes a read-only output.** The old module writes
#    `kdn.disks.persist.<bucket>.{directories,files}`, and the `disks` area has no den home yet. So
#    the aspect publishes `kdn.apps-persist` instead, and the consumer wires it in one line:
#
#        kdn.disks.persist = lib.mapAttrs (bucket: directories: {
#          inherit directories;
#          files = config.kdn.apps-persist.files.${bucket};
#        }) config.kdn.apps-persist.directories;
#
# 3. **Every path list gets `default = [ ]`.** Five of the twelve path options carried no default in
#    the old module, so an enabled application that named none of them stopped the evaluation with
#    "option used but not defined". A default of `[ ]` keeps every case that evaluated before, and
#    it removes that trap for an adopter.
#
# ## The `enable` flag inside the submodule stays
#
# Rule 2 below forbids a **reachable** `enable`. `checks/standalone.nix` walks the option tree and
# stops at an `attrsOf submodule`, so a per-instance flag is out of reach and it keeps its name.
# The flag is also the whole point of the option: a profile turns one application on by name.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See the paragraph above for the one flag that
#    an `attrsOf submodule` keeps out of reach.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.apps.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn;

      # The `apply` pipeline of the old `kdn.env.packages`, as a plain function. It drops a broken,
      # unsupported, unavailable or non-evaluating package and it warns once per group.
      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      # One path list, relative to `prefix`. An entry that starts with `/` is already relative to
      # the home directory, so it keeps its own place and only loses the leading slash.
      mkPathsOption =
        prefix:
        lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "my-app" ];
          apply = map (
            dir:
            if prefix == "" || lib.strings.hasPrefix "/" dir then
              lib.strings.removePrefix "/" dir
            else
              "${prefix}/${dir}"
          );
          description = ''
            Paths this application keeps, each one relative to `${
              if prefix == "" then "the home directory" else prefix
            }`.

            An entry that starts with `/` stays where it is and only loses the leading slash.
          '';
        };

      enabledApps = lib.filter (app: app.enable) (builtins.attrValues cfg.apps);

      collect = get: lib.concatMap get enabledApps;
    in
    {
      options.kdn.apps = lib.mkOption {
        default = { };
        example = lib.literalExpression ''
          {
            firefox.enable = true;
            firefox.dirs.config = [ ".mozilla/firefox" ];
          }
        '';
        description = ''
          One entry per application this user runs. The attribute name is the package name in
          nixpkgs, unless the entry overrides `name`.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }@appAttrs:
            let
              app = appAttrs.config;
            in
            {
              options.enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Run this application. A disabled entry installs no package and keeps no path.
                '';
              };

              options.name = lib.mkOption {
                type = lib.types.str;
                default = name;
                defaultText = lib.literalExpression "the attribute name";
                description = "The nixpkgs attribute name of the application.";
              };

              options.dirs.cache = mkPathsOption ".cache";
              options.dirs.config = mkPathsOption ".config";
              options.dirs.data = mkPathsOption ".local/share";
              options.dirs.disposable = mkPathsOption "";
              options.dirs.reproducible = mkPathsOption "";
              options.dirs.state = mkPathsOption ".local/state";

              options.files.cache = mkPathsOption ".cache";
              options.files.config = mkPathsOption ".config";
              options.files.data = mkPathsOption ".local/share";
              options.files.disposable = mkPathsOption "";
              options.files.reproducible = mkPathsOption "";
              options.files.state = mkPathsOption ".local/state";

              options.package.original = lib.mkOption {
                type = lib.types.nullOr lib.types.package;
                default = pkgs.${app.name};
                defaultText = lib.literalExpression "pkgs.\${config.name}";
                description = "The package before any overlay runs.";
              };

              options.package.overlays = lib.mkOption {
                type = lib.types.listOf (lib.types.functionTo (lib.types.attrsOf lib.types.anything));
                default = [ ];
                description = ''
                  Functions this tree folds into one `override` call, in order. Each one takes the
                  previous argument set and returns the next one.
                '';
              };

              options.package.final = lib.mkOption {
                type = lib.types.package;
                default = app.package.original.override (
                  prev: lib.lists.foldl (old: fn: fn old) prev app.package.overlays
                );
                defaultText = lib.literalExpression "config.package.original with every overlay applied";
                description = "The package this user installs and other modules read back.";
              };

              options.package.install = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = ''
                  Put the final package in `home.packages`. Turn it off when another module already
                  installs the application, for example a Home Manager program module.
                '';
              };
            }
          )
        );
      };

      options.kdn.apps-persist.directories = lib.mkOption {
        readOnly = true;
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = {
          "usr/cache" = collect (app: app.dirs.cache);
          "usr/config" = collect (app: app.dirs.config);
          "usr/data" = collect (app: app.dirs.data);
          "usr/state" = collect (app: app.dirs.state);
          "usr/reproducible" = collect (app: app.dirs.reproducible);
          "disposable" = collect (app: app.dirs.disposable);
        };
        description = ''
          Every directory the enabled applications keep, grouped by bucket. It is read-only: the
          value comes from `kdn.apps`.

          The old tree writes these lists straight into `kdn.disks.persist`. The `disks` area has no
          den home yet, so the consumer wires them:

              kdn.disks.persist = lib.mapAttrs (bucket: directories: {
                inherit directories;
                files = config.kdn.apps-persist.files.''${bucket};
              }) config.kdn.apps-persist.directories;
        '';
      };

      options.kdn.apps-persist.files = lib.mkOption {
        readOnly = true;
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = {
          "usr/cache" = collect (app: app.files.cache);
          "usr/config" = collect (app: app.files.config);
          "usr/data" = collect (app: app.files.data);
          "usr/state" = collect (app: app.files.state);
          "usr/reproducible" = collect (app: app.files.reproducible);
          "disposable" = collect (app: app.files.disposable);
        };
        description = ''
          Every single file the enabled applications keep, grouped by the same buckets as
          `kdn.apps-persist.directories`. It is read-only.
        '';
      };

      config.home.packages = filterPackages (
        collect (app: lib.optional app.package.install app.package.final)
      );
    };
}
