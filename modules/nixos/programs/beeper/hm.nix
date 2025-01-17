{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.beeper;
in {
  options.kdn.programs.beeper = {
    enable = lib.mkEnableOption "beeper messenger setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.apps."beeper" = {
        enable = true;
        dirs.cache = [];
        dirs.config = ["Beeper"];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    }
  ]);
}
