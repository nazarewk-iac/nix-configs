{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.hardware.modem;
in
{
  options.nazarewk.hardware.modem = {
    enable = mkEnableOption "modem (LTE + calls) setup";
  };

  config = mkIf cfg.enable {
    networking.networkmanager.enable = true;
    systemd.services.ModemManager.enable = true;
    systemd.services.ModemManager.wantedBy = [ "NetworkManager.service" ];

    # Phone calls
    programs.calls.enable = true;
  };
}
