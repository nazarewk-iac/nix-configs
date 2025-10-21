{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.programs.kdeconnect;
in
{
  options.kdn.programs.kdeconnect = {
    enable = lib.mkEnableOption "kdeconnect setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.kdeconnect.enable = true;
        services.kdeconnect.indicator = true;
        services.kdeconnect.package = config.kdn.programs.apps.kdeconnect.package.final;
        kdn.programs.apps.kdeconnect = {
          enable = true;
          package.original = pkgs.kdePackages.kdeconnect-kde;
          dirs.cache = [ ];
          dirs.config = [ "kdeconnect" ];
          dirs.data = [ ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
        };
      }
    ]
  );
}
