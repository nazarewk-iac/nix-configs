# A small FHS sandbox that runs the **installed** Strata Terminal on NixOS.
#
# Nothing is packaged from source here. The Terminal and its engine are runtime
# downloads from Strata's signed feed: `strata launch` fetches the engine for the
# card, `strata update` replaces it, and each engine package carries a signature
# that the Terminal checks. Both therefore live on a host path, outside the
# store. This derivation holds only the sandbox and a launcher, so an update to
# the Terminal or to the engine does not change any store path.
#
# The two library lists below are measured, not guessed; see README.md beside
# this file for the `ldd` output, the comparison with `steam-run`,
# `programs.nix-ld` and `autoPatchelfHook`, and the test log.
{
  lib,
  buildFHSEnvBubblewrap,
  writeShellScript,
  # The installed Terminal launcher. `current` is a symlink that `strata update`
  # repoints, so this path survives a Terminal upgrade.
  terminal ? "/var/lib/kdn/llms/models/.bench/strata/terminal/current/bin/strata",
  # The XDG data root of the install that holds the engine. The Terminal keeps
  # the engine in `$XDG_DATA_HOME/strata/components`, but it reads that folder
  # from `STRATA_COMPONENTS_DIR` first, so this package sets that one variable
  # instead of overriding `XDG_DATA_HOME` for every other XDG lookup.
  dataHome ? "/var/lib/kdn/llms/models/.bench/xdg",
  # A consumer with another need adds packages to the sandbox:
  #   pkgs.kdn.strata.override { extraPkgs = p: [ p.openssl ]; }
  extraPkgs ? (_: [ ]),
}:
let
  # Runs inside the sandbox that buildFHSEnvBubblewrap set up. It does not parse
  # arguments: `launch`, `components`, `update`, `doctor`, `--help` and the rest
  # reach the Terminal unchanged.
  launcher = writeShellScript "strata-launcher" ''
    set -eu

    # A runtime download, so a host path and never a store path. The caller can
    # name another install with STRATA_TERMINAL.
    default_terminal=${lib.escapeShellArg terminal}
    terminal="''${STRATA_TERMINAL:-$default_terminal}"

    if [ ! -x "$terminal" ]; then
      echo "strata: no runnable Terminal at $terminal" >&2
      echo "        install Strata, or set STRATA_TERMINAL=<install>/bin/strata" >&2
      exit 127
    fi

    # The engine lives in $XDG_DATA_HOME/strata/components. Point the Terminal at
    # that folder of the install this package was built for, unless the caller
    # named one: STRATA_COMPONENTS_DIR is the Terminal's own setting for exactly
    # this folder, and `--components-dir` still wins over it on the command line.
    if [ -z "''${STRATA_COMPONENTS_DIR:-}" ]; then
      STRATA_COMPONENTS_DIR=${lib.escapeShellArg "${dataHome}/strata/components"}
      export STRATA_COMPONENTS_DIR
    fi

    exec "$terminal" "$@"
  '';
in
buildFHSEnvBubblewrap {
  pname = "strata";
  # The wrapper has no upstream version of its own. The Terminal and the engine
  # carry their own versions and change under `strata update`.
  version = "0";

  runScript = launcher;
  executableName = "strata";

  # The FHS base set already provides, and no entry below repeats:
  #   glibc, which installs /lib64/ld-linux-x86-64.so.2 — the interpreter both
  #     the bundled CPython and the engine ELF ask for;
  #   gcc.cc.lib, which provides libstdc++.so.6 and libgcc_s.so.1;
  #   bashInteractiveFHS and coreutils, for the Terminal's `bin/strata` shell
  #     script (`dirname`, `readlink`, `test`).
  #
  # The two entries are exactly what `ldd` reports as `not found` across both
  # trees. `libstdc++.so.6` is reported too, and the base set covers it.
  targetPkgs =
    p:
    [
      # libz.so.1: numpy's `_multiarray_umath`, its bundled libgfortran and
      # libscipy_openblas, `_umath_linalg`, `lapack_lite`, and Pillow's
      # `_imaging`, `_imagingft` plus its bundled freetype, harfbuzz, libpng and
      # libtiff.
      p.zlib
      # libcrypt.so.1: the stdlib `_crypt` module of the bundled CPython.
      p.libxcrypt
    ]
    ++ extraPkgs p;

  # The default bubblewrap arguments bind every top-level directory of the host
  # root, so `/var/lib/...` (the Terminal and the engine) and `/nix/store` are
  # both visible inside the sandbox. It also binds `/sys` and `/dev`, which the
  # HIP runtime needs for KFD and the DRM nodes. No extra bind is required.
  passthru.extraPkgs = extraPkgs;

  meta = {
    description = "Strata Terminal launcher in a minimal FHS sandbox";
    homepage = "https://github.com/Niko1221/Strata";
    license = lib.licenses.mit;
    # Strata publishes engine packages for linux-x86_64 only.
    platforms = [ "x86_64-linux" ];
  };
}
