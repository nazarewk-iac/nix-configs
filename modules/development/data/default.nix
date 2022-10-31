{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.data;

  yq = "${cfg.packages.yq}/bin/yq";
  yj = "${cfg.packages.yj}/bin/yj";
  miller = "${cfg.packages.miller}/bin/mlr";

  converter = name: opts: pkgs.writeShellApplication {
    name = name;
    runtimeInputs = opts.pkgs;
    text = ''
      args=(${escapeShellArgs opts.args})
      files=()
      for arg in "$@" ; do
        if [[ "$arg" = -* ]]; then
          args+=("$arg")
        else
          files+=("$arg")
        fi
      done
      case "''${#files[@]}" in
        0) "''${args[@]}" ;;
        1) "''${args[@]}" < "''${files[0]}" ;;
        2) "''${args[@]}" < "''${files[0]}" > "''${files[1]}" ;;
        *)
          echo 'only 2 files (input and output) can be passed!'
          exit 1
        ;;
      esac
    '';
  };

  converterPkgs = mapAttrs (name: opts: converter name opts) {
    "csv2json" = { pkgs = [ miller ]; args = [ "mlr" "--icsv" "--ojson" "cat" ]; };
    "csv2jsonl" = { pkgs = [ miller ]; args = [ "mlr" "--icsv" "--ojsonl" "cat" ]; };
    "hcl2hcl" = { pkgs = [ yj ]; args = [ "yj" "-cc" ]; };
    "hcl2json" = { pkgs = [ yj ]; args = [ "yj" "-cj" ]; };
    "hcl2toml" = { pkgs = [ yj ]; args = [ "yj" "-ct" ]; };
    "hcl2yaml" = { pkgs = [ yj ]; args = [ "yj" "-cy" ]; };
    "json2hcl" = { pkgs = [ yj ]; args = [ "yj" "-jc" ]; };
    "json2json" = { pkgs = [ yj ]; args = [ "yj" "-jj" ]; };
    "json2toml" = { pkgs = [ yj ]; args = [ "yj" "-jt" ]; };
    "json2yaml" = { pkgs = [ yj ]; args = [ "yj" "-jy" ]; };
    "toml2hcl" = { pkgs = [ yj ]; args = [ "yj" "-tc" ]; };
    "toml2json" = { pkgs = [ yj ]; args = [ "yj" "-tj" ]; };
    "toml2toml" = { pkgs = [ yj ]; args = [ "yj" "-tt" ]; };
    "toml2yaml" = { pkgs = [ yj ]; args = [ "yj" "-ty" ]; };
    "yaml2hcl" = { pkgs = [ yj ]; args = [ "yj" "-yc" ]; };
    "yaml2json" = { pkgs = [ yq ]; args = [ "yq" "-M" "--" ]; };
    "yaml2toml" = { pkgs = [ yj ]; args = [ "yj" "-yt" ]; };
    "yaml2yaml" = { pkgs = [ yj ]; args = [ "yj" "-yy" ]; };
    "yamls2json" = { pkgs = [ yq ]; args = [ "yq" "-M" "[inputs]" "--" ]; };
  };
  conv = mapAttrs (name: pkg: "${pkg}/bin/${name}") converterPkgs;
in
{
  options.kdn.development.data = {
    enable = lib.mkEnableOption "tools for working with data";

    packages = {
      yq = mkOption {
        type = types.package;
        default = pkgs.yq-go;
      };

      yj = mkOption {
        type = types.package;
        default = pkgs.yj;
      };

      miller = mkOption {
        type = types.package;
        default = pkgs.miller;
      };

      jq = mkOption {
        type = types.package;
        default = pkgs.jq;
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = (with pkgs; [
      cfg.packages.miller
      cfg.packages.yq
      cfg.packages.jq
      cfg.packages.yj
      jq
      gojq

      jiq
      cue
      conftest

      gnused
    ]) ++ (attrValues converterPkgs);
  };
}
