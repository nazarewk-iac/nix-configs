# adapted from https://stackoverflow.com/a/54505212
{ lib, ... }:
let
  out = rec {
    isSupported = pkgs: lib.meta.availableOn pkgs.stdenv.hostPlatform;
    onlySupported =
      pkgs: pkg:
      lib.pipe pkg [
        lib.lists.toList
        (builtins.filter (isSupported pkgs))
      ];
  };
in
out
