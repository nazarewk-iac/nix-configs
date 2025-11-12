{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.browsers;
in {
  options.kdn.programs.browsers = {
    enable = lib.mkEnableOption "`browsers` selector setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.apps.browsers = {
          enable = true;
          dirs.cache = [];
          dirs.config = ["software.Browsers"];
          dirs.data = [];
          dirs.disposable = [];
          dirs.reproducible = [];
          dirs.state = [];
        };
      }
    ]
  );
}
