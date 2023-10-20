{ lib
, writeScriptBin
, python3
}:
writeScriptBin "path-search" ''
  #!${python3}/bin/python
  ${builtins.readFile ./path-search.py}
''
