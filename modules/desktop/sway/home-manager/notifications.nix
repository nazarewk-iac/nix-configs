{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.desktop.sway;
in
{
  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) {
    services.dunst.enable = true;
    services.dunst.settings = {
      global = {
        idle_threshold = "15s";
        ignore_dbusclose = true;
        timeout = "30m";
      };
    };
  };
}
