{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.data;

  yjConverter = name: flags: pkgs.writeShellApplication {
    name = name;
    runtimeInputs = with pkgs; [ yj ];
    text = ''
    args=(${flags})
    files=()
    for arg in "$@" ; do
      if [[ "$arg" = -* ]]; then
        args+=("$arg")
      else
        files+=("$arg")
      fi
    done
    case "''${#files[@]}" in
      0) yj "''${args[@]}" ;;
      1) yj "''${args[@]}" < "''${files[0]}" ;;
      2) yj "''${args[@]}" < "''${files[0]}" > "''${files[1]}" ;;
      *)
        echo 'only 2 files (input and output) can be passed!'
        exit 1
      ;;
    esac

    '';
  };
in {
  options.nazarewk.development.data = {
    enable = mkEnableOption "tools for working with data";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      jq
      cue

      gnused

      yj
      (yjConverter "hcl2hcl"    "-cc")
      (yjConverter "hcl2json"   "-cj")
      (yjConverter "hcl2toml"   "-ct")
      (yjConverter "hcl2yaml"   "-cy")
      (yjConverter "json2hcl"   "-jc")
      (yjConverter "json2json"  "-jj")
      (yjConverter "json2toml"  "-jt")
      (yjConverter "json2yaml"  "-jy")
      (yjConverter "toml2hcl"   "-tc")
      (yjConverter "toml2json"  "-tj")
      (yjConverter "toml2toml"  "-tt")
      (yjConverter "toml2yaml"  "-ty")
      (yjConverter "yaml2hcl"   "-yc")
      (yjConverter "yaml2json"  "-yj")
      (yjConverter "yaml2toml"  "-yt")
      (yjConverter "yaml2yaml"  "-yy")
    ];
  };
}