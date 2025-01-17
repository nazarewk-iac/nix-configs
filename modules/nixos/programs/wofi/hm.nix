{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.wofi;
in {
  options.kdn.programs.wofi = {
    enable = lib.mkEnableOption "`wofi` selector setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.apps.wofi = {
        enable = true;
        dirs.cache = [];
        dirs.config = [];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
        files.cache = ["wofi-run"];
      };
    }
  ]);
}
