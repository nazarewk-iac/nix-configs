{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.lua;

  mkAltLua = major: minor:
    let
      M = toString major;
      m = toString minor;
      suffixedBinaries = pkg: suffix: pkgs.runCommand "${pkg.name}-suffixed-bin-${suffix}" { } ''
        mkdir -p $out/bin
        for src in ${pkg}/bin/* ; do
          dst="''${src##*/}${suffix}"
          ln -s "$src" "$out/bin/$dst"
        done
      '';
    in
    suffixedBinaries pkgs."lua${M}_${m}" "${M}.${m}";
in
{
  options.nazarewk.development.lua = {
    enable = mkEnableOption "lua development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      lua5_4 # latest
      (mkAltLua 5 1) # argocd
      (mkAltLua 5 2)
      (mkAltLua 5 3)
      (mkAltLua 5 4)
    ];
  };
}
