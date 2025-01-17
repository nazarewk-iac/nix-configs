{
  lib,
  pkgs,
  config,
  system,
  ...
}: let
  cfg = config.kdn.desktop.remote-server;
in {
  options.kdn.desktop.remote-server = {
    enable = lib.mkEnableOption "remote desktop server setup";
  };

  config = lib.mkIf cfg.enable {
    services.teamviewer.enable = true;
  };
}
