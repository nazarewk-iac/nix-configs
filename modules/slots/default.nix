{ lib, ... }:
let
  allFiles = lib.filesystem.listFilesRecursive ./.;
  slotModules = builtins.filter (
    p:
    let
      s = toString p;
    in
    lib.hasSuffix "/default.nix" s && p != ./default.nix
  ) allFiles;
in
{
  imports = slotModules;

  options.kdn.isSourceRepo = lib.mkEnableOption ''
    marks this devenv as the nix-configs source repository itself.

    When true, devenv slots skip installing agent skills as nix-store symlinks —
    those files are instead committed directly to git as relative symlinks pointing
    into modules/slots/.  Derivative repos leave this false and get the symlinks.
  '';
}
