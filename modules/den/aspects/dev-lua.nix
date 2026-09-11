# The `development/lua` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs one Lua interpreter per version in `versions`, each with the same extra Lua packages.
# The default version keeps the plain binary names. Every other version gets a copy of its binaries
# with the version as a suffix, so `lua5.1` and `lua5.4` live side by side.
#
# ## One declaration, three classes
#
# The four options live in the `declaration` module below, and each target imports it. Only one class
# loads per evaluation, so the module system sees exactly one declaration each time.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The option prefix becomes `kdn.dev-lua`.** Every other option keeps its name and its default.
# 3. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#    through ../common/filter-packages.nix. Design B.
# 4. **The forward to Home Manager goes.** den needs no forward: a consumer names the class it
#    wants.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  declaration =
    { lib, ... }:
    {
      options.kdn.dev-lua.extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "luacheck"
          "luarepl"
          "luarocks"
          "lyaml"
          "stdlib"
        ];
        description = "The Lua packages each interpreter carries, by attribute name.";
      };

      options.kdn.dev-lua.brokenPackages = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = {
          "5.4" = [ "luacheck" ];
        };
        description = ''
          The packages to drop, per Lua version. A package that does not build for one version stays
          available for every other version.
        '';
      };

      options.kdn.dev-lua.defaultVersion = lib.mkOption {
        type = lib.types.str;
        default = "5.4";
        description = "The version that keeps the plain binary names, without a suffix.";
      };

      options.kdn.dev-lua.versions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "5.1" # argocd
          "5.2"
          "5.3"
          "5.4"
        ];
        description = "Every version to install with suffixed binary names.";
      };
    };

  packagesOf =
    {
      config,
      lib,
      pkgs,
    }:
    let
      cfg = config.kdn.dev-lua;

      mkLuaVersion =
        version:
        let
          pkg = pkgs."lua${lib.replaceStrings [ "." ] [ "_" ] version}";
          selectedPackages = lib.subtractLists (cfg.brokenPackages.${version} or [ ]) cfg.extraPackages;
        in
        pkg.withPackages (ps: map (n: ps.${n}) selectedPackages);

      suffixedBinaries =
        pkg: suffix:
        pkgs.runCommand "${pkg.name}-suffixed-bin-${suffix}" { } ''
          mkdir -p $out/bin
          for src in ${pkg}/bin/* ; do
            dst="''${src##*/}${suffix}"
            ln -s "$src" "$out/bin/$dst"
          done
        '';

      mkSuffixedLuaVersion = v: suffixedBinaries (mkLuaVersion v) v;
    in
    import ../common/filter-packages.nix { inherit lib; } (
      [
        (mkLuaVersion cfg.defaultVersion) # the latest one
      ]
      ++ (map mkSuffixedLuaVersion cfg.versions)
    );

  systemTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      environment.systemPackages = packagesOf { inherit config lib pkgs; };
    };
in
{
  kdn.dev-lua.nixos = systemTarget;
  kdn.dev-lua.darwin = systemTarget;

  kdn.dev-lua.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      home.packages = packagesOf { inherit config lib pkgs; };

      programs.helix.extraPackages = with pkgs; [ lua-language-server ];
    };
}
