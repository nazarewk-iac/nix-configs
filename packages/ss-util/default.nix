{
  pkgs,
  lib,
  ...
}: let
  python = pkgs.python313;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (file: file.hasExt "py") ./ss_util;
  };
in
  lib.kdn.mkPythonScript pkgs {
    inherit src python;
    name = "ss-util";
    pythonModule = "ss_util.cli";
    requirementsFileText = ''
      click
      structlog
      rich
      secretstorage
      cryptography
    '';
  }
