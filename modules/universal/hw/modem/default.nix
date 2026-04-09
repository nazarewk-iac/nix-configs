{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.hw.modem;
in
{
  options.kdn.hw.modem = {
    enable = lib.mkEnableOption "modem (LTE + calls) setup";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      networking.networkmanager.enable = lib.mkDefault true;
      systemd.services.ModemManager.enable = lib.mkDefault true;
      systemd.services.ModemManager.wantedBy = [ "NetworkManager.service" ];
    }
  );
}
