{ pkgs, inputs, ... }:
let
  lib = pkgs.lib;
  customPackages = pkgs.callPackage ./custom.nix { };
in
{
  kdn = lib.trivial.pipe ./. [
    lib.filesystem.listFilesRecursive
    # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
    (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
    (builtins.map (path: {
      name =
        let
          pieces = lib.splitString "/" (toString path);
          len = builtins.length pieces;
        in
        builtins.elemAt pieces (len - 2);
      value = pkgs.callPackage path { inherit inputs; };
    }))
    (builtins.filter (e: !(customPackages ? e.name)))
    builtins.listToAttrs
    (out: out // customPackages)
  ];
}
