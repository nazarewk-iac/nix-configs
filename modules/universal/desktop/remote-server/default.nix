{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.desktop.remote-server;
in
{
  options.kdn.desktop.remote-server = {
    enable = lib.mkEnableOption "remote desktop server setup";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      services.teamviewer.enable = true;
    }
  );
}
