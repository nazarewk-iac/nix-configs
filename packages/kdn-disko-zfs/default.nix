{
  pkgs,
  lib,
  __inputs__ ? { },
  ...
}:
let
  python = pkgs.python314;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (file: file.hasExt "py") ./kdn_disko_zfs;
  };

  mkPythonScript =
    if __inputs__ ? inputs.kdn-configs-src then
      import (__inputs__.inputs.kdn-configs-src + /lib/python/mkPythonScript.nix) { inherit lib pkgs; }
    else
      lib.kdn.mkPythonScript pkgs;
in
# The binary is stdlib-only. `disko-zfs` itself is NOT baked in: the wrapper
# resolves it for the TARGET host's architecture at runtime (devenv's copy when
# the arch matches, else a nix build from this repo's pinned flake input).
# `runtimeDeps` are the non-Python tools it shells out to.
mkPythonScript {
  inherit src python;
  name = "kdn-disko-zfs";
  pythonModule = "kdn_disko_zfs.cli";
  requirementsFileText = "";
  runtimeDeps = with pkgs; [
    nix
    openssh
    coreutils
  ];
}
