{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.orca-slicer;
in {
  options.kdn.programs.orca-slicer = {
    enable = lib.mkEnableOption "orca-slicer setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.apps.orca-slicer = {
          enable = true;
          package.original = pkgs.orca-slicer.overrideAttrs (
            finalAttrs: previousAttrs: {
              version = "2024-10-23-425d9c";
              pname = "orca-slicer";

              src = pkgs.fetchFromGitHub {
                owner = "SoftFever";
                repo = "OrcaSlicer";
                rev = "425d9c97e404bd56d64d2b98e98013855935ed8f";
                hash = "sha256-WrjZLRlwlNB7w/QjPCO9/QTcaCTpRmOxp7vJnnzr2yQ=";
              };
              patches = let
                ignoredPatchSuffixes = [
                  "meshboolean-const.patch"
                  "0002-fix-build-for-gcc-13.diff"
                ];
              in
                builtins.filter (
                  p: let
                    patchFileName = toString p;
                  in
                    !(builtins.any (
                        filenameSuffix: lib.strings.hasSuffix filenameSuffix patchFileName
                      )
                      ignoredPatchSuffixes)
                )
                previousAttrs.patches;
            }
          );
          dirs.cache = ["orca-slicer"];
          dirs.config = ["OrcaSlicer"];
          dirs.data = ["orca-slicer"];
          dirs.disposable = [];
          dirs.reproducible = [];
          dirs.state = [];
        };
      }
    ]
  );
}
