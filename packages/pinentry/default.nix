{
  lib,
  python3,
  pinentry-curses,
  pinentry-gtk2,
  pinentry_mac,
  pinentry-qt,
  stdenv,
  writeScriptBin,
}:
let
  plat = stdenv.hostPlatform;

  runtimeInputs =
    lib.optionals (plat.isDarwin) [
      pinentry_mac
    ]
    ++ lib.optionals (plat.isLinux || plat.isDarwin && plat.isx86_64) [
      pinentry-qt
    ]
    ++ [
      pinentry-gtk2
      pinentry-curses
    ];
in
writeScriptBin "pinentry" ''
  #!${python3}/bin/python
  import os
  os.environ["PATH"] = f'${lib.makeBinPath runtimeInputs}:os.environ.get("PATH", "")'.strip(os.path.pathsep)
  ${builtins.readFile ./pinentry.py}
''
