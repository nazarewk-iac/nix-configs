{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.kdeconnect;
in {
  options.kdn.programs.kdeconnect = {
    enable = lib.mkEnableOption "kdeconnect setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.kdeconnect.enable = true;
      services.kdeconnect.indicator = true;
      services.kdeconnect.package = cfg.package.final;
      kdn.programs.apps.kdeconnect = {
        enable = true;
        dirs.cache = [];
        dirs.config = ["kdeconnect"];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    }
  ]);
}
