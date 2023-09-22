{ lib
, miller
, pkgs
, symlinkJoin
, writeShellApplication
, yj
, yq-go
, ...
}:
let
  mkConverterScript = name: args: writeShellApplication {
    name = name;
    text = ''
      run() {
        ${lib.escapeShellArgs args}
      }
      case "$#" in
        0) run ;;
        1) run < "$1" ;;
        2) run < "$1" > "$2" ;;
        *)
          echo 'only 2 files (input and output) can be passed!' >&2
          exit 1
        ;;
      esac
    '';
  };
in
symlinkJoin {
  name = "data-converters";
  paths = lib.attrsets.mapAttrsToList mkConverterScript {
    "csv2json" = [ "${miller}/bin/mlr" "--icsv" "--ojson" "cat" ];
    "csv2jsonl" = [ "${miller}/bin/mlr" "--icsv" "--ojsonl" "cat" ];
    "hcl12hcl1" = [ "${yj}/bin/yj" "-cc" ];
    "hcl12json" = [ "${yj}/bin/yj" "-cj" ];
    "hcl12toml" = [ "${yj}/bin/yj" "-ct" ];
    "hcl12yaml" = [ "${yj}/bin/yj" "-cy" ];
    "json2hcl1" = [ "${yj}/bin/yj" "-jc" ];
    "json2json" = [ "${yj}/bin/yj" "-jj" ];
    "json2toml" = [ "${yj}/bin/yj" "-jt" ];
    "json2yaml" = [ "${yj}/bin/yj" "-jy" ];
    "toml2hcl1" = [ "${yj}/bin/yj" "-tc" ];
    "toml2json" = [ "${yj}/bin/yj" "-tj" ];
    "toml2toml" = [ "${yj}/bin/yj" "-tt" ];
    "toml2yaml" = [ "${yj}/bin/yj" "-ty" ];
    "yaml2hcl1" = [ "${yj}/bin/yj" "-yc" ];
    "yaml2json" = [ "${yq-go}/bin/yq" "eval" "--indent=0" "--no-colors" "--output-format=json" "--" ];
    "yaml2toml" = [ "${yj}/bin/yj" "-yt" ];
    "yaml2yaml" = [ "${yj}/bin/yj" "-yy" ];
    # see for making array out of documents https://github.com/mikefarah/yq/discussions/993
    "yamls2json" = [ "${yq-go}/bin/yq" "eval-all" "--indent=0" "--no-colors" "--output-format=json" "[.]" "--" ];
  };
}
