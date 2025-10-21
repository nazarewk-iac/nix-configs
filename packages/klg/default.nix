{
  pkgs,
  lib,
  ...
}:
let
  python = pkgs.python313;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (file: file.hasExt "py") ./klg;
  };
in
lib.kdn.mkPythonScript pkgs {
  inherit src python;
  name = "klg";
  pythonModule = "klg.cli";
  requirementsFileText = ''
    asyncclick
    trio
    anyio
    async-cache
    pendulum
    structlog
    rich
    dacite
    xdg-base-dirs
  '';
}
