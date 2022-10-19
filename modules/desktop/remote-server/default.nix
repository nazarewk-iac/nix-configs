{ lib, pkgs, config, system, ... }:
with lib;
let
  cfg = config.kdn.desktop.remote-server;
in
{
  options.kdn.desktop.remote-server = {
    enable = lib.mkEnableOption "remote desktop server setup";
  };

  config = mkIf cfg.enable {
    services.teamviewer.enable = true;
  };
}
