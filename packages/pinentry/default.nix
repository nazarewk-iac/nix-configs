{ lib, python3, pinentry-qt, pinentry-curses, writeScriptBin }:
let
  runtimeInputs = [
    pinentry-qt
    pinentry-curses
  ];
in
writeScriptBin "pinentry" ''
  #!${python3}/bin/python
  import os
  os.environ["PATH"] = f'${lib.makeBinPath runtimeInputs}:os.environ.get("PATH", "")'.strip(os.path.pathsep)
  ${builtins.readFile ./pinentry.py}
''
