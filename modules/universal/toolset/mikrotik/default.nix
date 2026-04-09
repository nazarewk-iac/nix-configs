{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.toolset.mikrotik;
in
{
  options.kdn.toolset.mikrotik = {
    enable = lib.mkEnableOption "mikrotik/RouterOS utils";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.toolset.mikrotik.enable = cfg.enable; } ];
      }
    ))
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        kdn.emulation.wine.enable = true;
        home.packages = with pkgs; [ (lib.lowPrio winbox) ];
        kdn.apps.winbox4 = {
          enable = true;
          dirs.cache = [ ];
          dirs.config = [ ];
          dirs.data = [ "MikroTik/WinBox" ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
        };
      }
    ))
  ];
}
