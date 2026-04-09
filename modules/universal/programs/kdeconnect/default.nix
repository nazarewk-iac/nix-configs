{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.kdeconnect;
in
{
  options.kdn.programs.kdeconnect = {
    enable = lib.mkEnableOption "kdeconnect setup";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          { home-manager.sharedModules = [ { kdn.programs.kdeconnect.enable = true; } ]; }
          {
            # takes care of firewall
            programs.kdeconnect.enable = true;
          }
        ]
      )
    ))
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        services.kdeconnect.enable = true;
        services.kdeconnect.indicator = true;
        services.kdeconnect.package = config.kdn.apps.kdeconnect.package.final;
        kdn.apps.kdeconnect = {
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
    ))
  ];
}
