{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.element;
in {
  options.kdn.programs.element = {
    enable = lib.mkEnableOption "element setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.apps.element-desktop = {
        enable = true;
        dirs.cache = [];
        dirs.config = ["Element"];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    }
  ]);
}
