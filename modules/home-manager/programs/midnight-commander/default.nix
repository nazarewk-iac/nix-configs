{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.midnight-commander;
  appCfg = config.kdn.programs.apps."mc";
in {
  options.kdn.programs.midnight-commander = {
    enable = lib.mkEnableOption "Midnight Commander configuration";
  };
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.programs.apps."mc" = {
          enable = true;
          package.install = false;
          dirs.cache = ["mc"];
          dirs.config = ["mc"];
          dirs.data = [];
          dirs.disposable = [];
          dirs.reproducible = [];
          dirs.state = [];
        };
        programs.mc.enable = true;
        programs.mc.package = appCfg.package.final;
      }
    ]
  );
}
