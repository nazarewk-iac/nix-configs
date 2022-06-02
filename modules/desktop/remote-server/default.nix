{ lib, pkgs, config, system, ... }:
with lib;
let
  cfg = config.nazarewk.desktop.remote-server;
in
{
  options.nazarewk.desktop.remote-server = {
    enable = mkEnableOption "remote desktop server setup";
  };

  config = mkIf cfg.enable {
    services.teamviewer.enable = true;
  };
}
