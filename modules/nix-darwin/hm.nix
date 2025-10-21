{
  lib,
  config,
  pkgs,
  ...
}:
{
  imports = [
    ../home-manager
  ]
  ++ lib.trivial.pipe ./. [
    # find all hm.nix files
    lib.filesystem.listFilesRecursive
    (lib.filter (path: (lib.hasSuffix "/hm.nix" (toString path)) && path != ./hm.nix))
  ];
}
