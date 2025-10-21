{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.toolset.mikrotik;
in
{
  options.kdn.toolset.mikrotik = {
    enable = lib.mkEnableOption "mikrotik/RouterOS utils";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      { home-manager.sharedModules = [ { kdn.toolset.mikrotik.enable = cfg.enable; } ]; }
    ]
  );
}
