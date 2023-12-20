{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.desktop.sway;
in
{
  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) {
    services.dunst.enable = true;
  };
}
