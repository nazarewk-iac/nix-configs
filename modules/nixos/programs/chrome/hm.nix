{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.chrome;
in {
  options.kdn.programs.chrome = {
    enable = lib.mkEnableOption "Google Chrome setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.apps.chrome = {
          enable = true;
          package.original = pkgs.google-chrome;
          dirs.cache = [];
          dirs.config = ["google-chrome"];
          dirs.data = [];
          dirs.disposable = [];
          dirs.reproducible = [];
          dirs.state = [];
        };
      }
    ]
  );
}
