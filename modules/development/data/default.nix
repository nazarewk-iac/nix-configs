{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.data;


  converter = name: opts: pkgs.writeShellApplication {
    name = name;
    runtimeInputs = opts.pkgs;
    text = ''
      args=(${lib.escapeShellArgs opts.args})
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

  converterPkgs = lib.mapAttrs (name: opts: converter name opts) {
    "csv2json" = { pkgs = [ cfg.packages.miller ]; args = [ "mlr" "--icsv" "--ojson" "cat" ]; };
    "csv2jsonl" = { pkgs = [ cfg.packages.miller ]; args = [ "mlr" "--icsv" "--ojsonl" "cat" ]; };
    "hcl12hcl1" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-cc" ]; };
    "hcl12json" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-cj" ]; };
    "hcl12toml" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-ct" ]; };
    "hcl12yaml" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-cy" ]; };
    "json2hcl1" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-jc" ]; };
    "json2json" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-jj" ]; };
    "json2toml" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-jt" ]; };
    "json2yaml" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-jy" ]; };
    "toml2hcl1" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-tc" ]; };
    "toml2json" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-tj" ]; };
    "toml2toml" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-tt" ]; };
    "toml2yaml" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-ty" ]; };
    "yaml2hcl1" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-yc" ]; };
    "yaml2json" = { pkgs = [ cfg.packages.yq ]; args = [ "yq" "eval" "--indent=0" "--no-colors" "--output-format=json" "--" ]; };
    "yaml2toml" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-yt" ]; };
    "yaml2yaml" = { pkgs = [ cfg.packages.yj ]; args = [ "yj" "-yy" ]; };
    # see for making array out of documents https://github.com/mikefarah/yq/discussions/993
    "yamls2json" = { pkgs = [ cfg.packages.yq ]; args = [ "yq" "eval-all" "--indent=0" "--no-colors" "--output-format=json" "[.]" "--" ]; };
  };
  conv = lib.mapAttrs (name: pkg: "${pkg}/bin/${name}") converterPkgs;
in
{
  options.kdn.development.data = {
    enable = lib.mkEnableOption "tools for working with data";

    packages = {
      yq = lib.mkOption {
        type = lib.types.package;
        default = pkgs.yq-go;
      };

      yj = lib.mkOption {
        type = lib.types.package;
        default = pkgs.yj;
      };

      miller = lib.mkOption {
        type = lib.types.package;
        default = pkgs.miller;
      };

      jq = lib.mkOption {
        type = lib.types.package;
        default = pkgs.jq;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = (with pkgs; [
      cfg.packages.miller
      cfg.packages.yq
      cfg.packages.jq
      cfg.packages.yj

      gojq
      jiq # interactive JQ
      jc # convert commands output to JSON
      gron # JSON to/from list of path-value assignments
      (pkgs.writeShellApplication {
        name = "ungron";
        runtimeInputs = with pkgs; [ gron ];
        text = ''gron --urgron "$@"'';
      })

      cue
      conftest

      opensearch # opensearch-cli

      gnused

      # Convert HCL <-> JSON
      python3Packages.bc-python-hcl2
      hcl2json
    ]) ++ (lib.attrValues converterPkgs);
  };
}
