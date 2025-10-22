{
  pkgs,
  lib,
  __inputs__ ? {},
  ...
}: let
  python = pkgs.python314;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (file: file.hasExt "py") ./package_placeholder;
  };

  mkPythonScript =
    if __inputs__ ? inputs.kdn-configs-src
    then import (__inputs__.inputs.kdn-configs-src + /lib/python/mkPythonScript.nix) {inherit lib pkgs;}
    else lib.kdn.mkPythonScript pkgs;
in
  mkPythonScript {
    inherit src python;
    name = "nix-name-placeholder";
    pythonModule = "package_placeholder.cli";
    requirementsFileText = ''
      fire
      structlog
    '';
    runtimeDeps = with pkgs; [
      #git
    ];
  }
