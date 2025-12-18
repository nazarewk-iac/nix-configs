{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.toolset.mikrotik;
in {
  options.kdn.toolset.mikrotik = {
    enable = lib.mkEnableOption "mikrotik/RouterOS utils";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.emulation.wine.enable = true;
      home.packages = with pkgs; [
        (lib.lowPrio winbox)
      ];
      kdn.apps.winbox4 = {
        enable = true;
        dirs.cache = [];
        dirs.config = [];
        dirs.data = ["MikroTik/WinBox"];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    }
  ]);
}
