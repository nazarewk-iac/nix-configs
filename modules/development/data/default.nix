{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.data;

  yq = cfg.packages.yq;
  yj = cfg.packages.yj;

  converter = name: cmd: flags: pkgs.writeShellApplication {
    name = name;
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
        0) "${cmd}" "''${args[@]}" ;;
        1) "${cmd}" "''${args[@]}" < "''${files[0]}" ;;
        2) "${cmd}" "''${args[@]}" < "''${files[0]}" > "''${files[1]}" ;;
        *)
          echo 'only 2 files (input and output) can be passed!'
          exit 1
        ;;
      esac

    '';
  };
in
{
  options.nazarewk.development.data = {
    enable = mkEnableOption "tools for working with data";

    packages = {
      yq = mkOption {
        type = types.package;
        default = pkgs.yq-go;
      };

      yj = mkOption {
        type = types.package;
        default = pkgs.yj;
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      yq
      yj
      jq
      cue

      gnused

      (converter "hcl2hcl" "${yj}/bin/yj" "-cc")
      (converter "hcl2json" "${yj}/bin/yj" "-cj")
      (converter "hcl2toml" "${yj}/bin/yj" "-ct")
      (converter "hcl2yaml" "${yj}/bin/yj" "-cy")
      (converter "json2hcl" "${yj}/bin/yj" "-jc")
      (converter "json2json" "${yj}/bin/yj" "-jj")
      (converter "json2toml" "${yj}/bin/yj" "-jt")
      (converter "json2yaml" "${yj}/bin/yj" "-jy")
      (converter "toml2hcl" "${yj}/bin/yj" "-tc")
      (converter "toml2json" "${yj}/bin/yj" "-tj")
      (converter "toml2toml" "${yj}/bin/yj" "-tt")
      (converter "toml2yaml" "${yj}/bin/yj" "-ty")
      (converter "yaml2hcl" "${yj}/bin/yj" "-yc")
      (converter "yaml2json" "${yq}/bin/yq" "-M --")
      (converter "yaml2toml" "${yj}/bin/yj" "-yt")
      (converter "yaml2yaml" "${yj}/bin/yj" "-yy")
      (converter "yamls2json" "${yq}/bin/yq" "-M '[inputs]' --")
    ];
  };
}
