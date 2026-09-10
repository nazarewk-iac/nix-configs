{
  lib,
  python3,
  pinentry-curses,
  pinentry-gnome3,
  pinentry_mac,
  pinentry-qt,
  stdenv,
  writeScriptBin,
}:
let
  plat = stdenv.hostPlatform;

  # Each entry needs a `meta.platforms` that holds this platform. A package that does not build
  # here stops the whole evaluation with "Refusing to evaluate package ... because it is not
  # available on the requested hostPlatform". `nix flake check` reads every `packages.<system>`
  # entry, so one such package fails the whole check on that system.
  runtimeInputs =
    lib.optionals plat.isDarwin [
      pinentry_mac
    ]
    # `pinentry-qt` is absent on `aarch64-darwin`. Measured 2026-09-10. The `&&` binds tighter
    # than the `||`; the parentheses only state that.
    ++ lib.optionals (plat.isLinux || (plat.isDarwin && plat.isx86_64)) [
      pinentry-qt
    ]
    # `pinentry-gnome3` is a GNOME program. nixpkgs lists Linux systems only in its
    # `meta.platforms` (<nixpkgs>/pkgs/tools/security/pinentry/default.nix:118).
    ++ lib.optionals plat.isLinux [
      pinentry-gnome3
    ]
    ++ [
      pinentry-curses
    ];
in
writeScriptBin "pinentry" ''
  #!${python3}/bin/python
  import os
  os.environ["PATH"] = f'${lib.makeBinPath runtimeInputs}:os.environ.get("PATH", "")'.strip(os.path.pathsep)
  ${builtins.readFile ./pinentry.py}
''
