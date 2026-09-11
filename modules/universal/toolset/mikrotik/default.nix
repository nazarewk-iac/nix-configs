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
    (lib.mkIf cfg.enable {
      kdn.env.packages = with pkgs; [ (lib.lowPrio winbox) ];
    })
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.toolset.mikrotik.enable = cfg.enable; } ];
      }
    ))
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        # Keep the plain priority. `emulation/wine` forwards its whole `cfg` into Home Manager at
        # `lib.mkDefault`, so a `lib.mkDefault true` here makes a 1000-to-1000 tie and stops the
        # evaluation of every workstation (measured 2026-09-11 on brys and oams).
        kdn.emulation.wine.enable = true;
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
