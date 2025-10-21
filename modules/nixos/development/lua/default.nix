{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.development.lua;

  mkLuaVersion =
    version:
    let
      pkg = pkgs."lua${lib.replaceStrings [ "." ] [ "_" ] version}";
      selectedPackages = lib.subtractLists (cfg.brokenPackages.${version} or [ ]) cfg.extraPackages;
    in
    pkg.withPackages (ps: map (n: ps.${n}) selectedPackages);

  mkSuffixedLuaVersion = v: suffixedBinaries (mkLuaVersion v) v;

  suffixedBinaries =
    pkg: suffix:
    pkgs.runCommand "${pkg.name}-suffixed-bin-${suffix}" { } ''
      mkdir -p $out/bin
      for src in ${pkg}/bin/* ; do
        dst="''${src##*/}${suffix}"
        ln -s "$src" "$out/bin/$dst"
      done
    '';
in
{
  options.kdn.development.lua = {
    enable = lib.mkEnableOption "lua development";

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "luacheck"
        "luarepl"
        "luarocks"
        "lyaml"
        "stdlib"
      ];
    };
    brokenPackages = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {
        "5.4" = [ "luacheck" ];
      };
    };

    defaultVersion = lib.mkOption {
      type = lib.types.str;
      default = "5.4";
    };

    versions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "5.1" # argocd
        "5.2"
        "5.3"
        "5.4"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [ { kdn.development.lua.enable = true; } ];
    environment.systemPackages =
      with pkgs;
      [
        (mkLuaVersion cfg.defaultVersion) # latest
      ]
      ++ (map mkSuffixedLuaVersion cfg.versions);
  };
}
