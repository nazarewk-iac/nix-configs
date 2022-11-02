{ lib, ... }:
lib.extend (final: prev:
let
  lib = prev.pipe ./packages [
    prev.filesystem.listFilesRecursive
    # prev.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
    (prev.filter (path: (prev.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
    (map (path:
      let
        fns = import path { prev = prev; };
        name =
          let pieces = prev.splitString "/" (toString path); len = builtins.length pieces;
          in builtins.elemAt pieces (len - 2);
      in
      { "${name}" = fns; } // fns))
    prev.mkMerge
    (libs: prev //
      { kdn = libs; }) # namespace packages to kdn
  ];
in
lib
)

