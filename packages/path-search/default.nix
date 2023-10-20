{ lib
, writeScriptBin
, python3
}:
writeScriptBin "path-search" ''
  #!${python3}
  ${builtins.readFile ./path-search.py}
''
