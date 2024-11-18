{
  lib,
  writeScriptBin,
  python3,
}:
writeScriptBin "whicher" ''
  #!${python3}/bin/python
  ${builtins.readFile ./whicher.py}
''
