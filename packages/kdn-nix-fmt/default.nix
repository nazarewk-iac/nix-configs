{
  pkgs,
  lib,
  __inputs__ ? {},
  ...
}: let
  python = pkgs.python313;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (file: file.hasExt "py") ./kdn_nix_fmt;
  };

  mkPythonScript =
    if __inputs__ ? inputs.kdn-configs-src
    then import (__inputs__.inputs.kdn-configs-src + /lib/python/mkPythonScript.nix) {inherit lib pkgs;}
    else lib.kdn.mkPythonScript pkgs;
in
  mkPythonScript {
    inherit src python;
    name = "kdn-nix-fmt";
    pythonModule = "kdn_nix_fmt.cli";
    requirementsFileText = ''
      fire
      structlog
    '';
    runtimeDeps = with pkgs; [
      alejandra
      nixfmt
    ];
  }
