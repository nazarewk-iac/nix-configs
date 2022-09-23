{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.lua;

  getLua = pkg: (pkg.withPackages (ps: map (n: ps.${n}) cfg.extraPackages));


  suffixedBinaries = pkg: suffix: pkgs.runCommand "${pkg.name}-suffixed-bin-${suffix}" { } ''
    mkdir -p $out/bin
    for src in ${pkg}/bin/* ; do
      dst="''${src##*/}${suffix}"
      ln -s "$src" "$out/bin/$dst"
    done
  '';
in
{
  options.nazarewk.development.lua = {
    enable = mkEnableOption "lua development";

    extraPackages = mkOption {
      type = types.listOf types.str;
      default = [
        "lyaml"
        "stdlib"
        "luarepl"
        "luarocks"
      ];
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (getLua lua5_4) # latest
      (suffixedBinaries (getLua lua5_1) "5.1") # argocd
      (suffixedBinaries (getLua lua5_2) "5.2")
      (suffixedBinaries (getLua lua5_3) "5.3")
      (suffixedBinaries (getLua lua5_4) "5.4")
    ];
  };
}
