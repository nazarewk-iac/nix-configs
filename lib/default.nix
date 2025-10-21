{ lib, ... }:
lib.extend (
  final: prev:
  let
    lib = final;
    callLibs = path: import path { inherit lib; };
    attrsets = callLibs ./attrsets/default.nix;

    kdn = lib.trivial.pipe ./. [
      lib.filesystem.listFilesRecursive
      # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
      (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
      (map (
        path:
        let
          cur = callLibs path;
          name =
            let
              pieces = lib.strings.splitString "/" (toString path);
              len = builtins.length pieces;
            in
            builtins.elemAt pieces (len - 2);
        in
        cur // { "${name}" = cur; }
      ))
      attrsets.recursiveMerge
    ];
  in
  {
    inherit kdn;
  }
)
