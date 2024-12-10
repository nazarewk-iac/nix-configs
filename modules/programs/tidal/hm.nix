{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.tidal;
in {
  options.kdn.programs.tidal = {
    enable = lib.mkEnableOption "tidal setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.apps.tidal = {
        enable = true;
        package.original = pkgs.tidal-hifi;
        dirs.cache = [];
        dirs.config = ["tidal-hifi"];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    }
  ]);
}
