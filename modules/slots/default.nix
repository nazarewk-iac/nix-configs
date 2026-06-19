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
}
