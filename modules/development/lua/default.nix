{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.lua;

  mkLuaVersion = version:
    let
      pkg = pkgs."lua${lib.replaceStrings ["."] ["_"] version}";
      selectedPackages = subtractLists (cfg.brokenPackages.${version} or [ ]) cfg.extraPackages;
    in
    pkg.withPackages (ps: map (n: ps.${n}) selectedPackages)
  ;

  mkSuffixedLuaVersion = v: suffixedBinaries (mkLuaVersion v) v;

  suffixedBinaries = pkg: suffix: pkgs.runCommand "${pkg.name}-suffixed-bin-${suffix}" { } ''
    mkdir -p $out/bin
    for src in ${pkg}/bin/* ; do
      dst="''${src##*/}${suffix}"
      ln -s "$src" "$out/bin/$dst"
    done
  '';
in
{
  options.kdn.development.lua = {
    enable = mkEnableOption "lua development";

    extraPackages = mkOption {
      type = types.listOf types.str;
      default = [
        "luacheck"
        "luarepl"
        "luarocks"
        "lyaml"
        "stdlib"
      ];
    };
    brokenPackages = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = {
        "5.4" = [ "luacheck" ];
      };
    };

    defaultVersion = mkOption {
      type = types.str;
      default = "5.4";
    };

    versions = mkOption {
      type = types.listOf types.str;
      default = [
        "5.1" # argocd
        "5.2"
        "5.3"
        "5.4"
      ];
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (mkLuaVersion cfg.defaultVersion) # latest
    ] ++ (map mkSuffixedLuaVersion cfg.versions);
  };
}
