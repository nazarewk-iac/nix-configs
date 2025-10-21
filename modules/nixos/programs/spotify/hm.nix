{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.programs.spotify;
in
{
  options.kdn.programs.spotify = {
    enable = lib.mkEnableOption "spotify setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.programs.apps.spotify = {
          enable = true;
          /*
            spotifywm> Running phase: unpackPhase
            spotifywm> unpacking source archive /nix/store/9m6wlhrdmas4czlhm5wbya70br20s1d3-source
            spotifywm> source root is source
            spotifywm> Running phase: patchPhase
            spotifywm> Running phase: updateAutotoolsGnuConfigScriptsPhase
            spotifywm> Running phase: configurePhase
            spotifywm> no configure script, doing nothing
            spotifywm> Running phase: buildPhase
            spotifywm> build flags: SHELL=/nix/store/q7sqwn7i6w2b67adw0bmix29pxg85x3w-bash-5.3p3/bin/bash
            spotifywm> g++ -Wall -Wextra -O3 -shared -fPIC -static-libgcc -lX11 -DSONAME="spotifywm.so" -o spotifywm.so spotifywm.cpp
            spotifywm> spotifywm.cpp:12:10: fatal error: xcb/xproto.h: No such file or directory
            spotifywm>    12 | #include <xcb/xproto.h>
            spotifywm>       |          ^~~~~~~~~~~~~~
            spotifywm> compilation terminated.
            spotifywm> make: *** [Makefile:10: spotifywm.so] Error 1
          */
          #package.original = pkgs.spotifywm;
          dirs.cache = [ "spotify" ];
          dirs.config = [ "spotify" ];
          dirs.data = [ ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
        };
      }
    ]
  );
}
