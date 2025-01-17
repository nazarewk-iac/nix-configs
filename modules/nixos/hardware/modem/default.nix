{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hardware.modem;
in {
  options.kdn.hardware.modem = {
    enable = lib.mkEnableOption "modem (LTE + calls) setup";
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager.enable = true;
    systemd.services.ModemManager.enable = true;
    systemd.services.ModemManager.wantedBy = ["NetworkManager.service"];

    # Phone calls
    programs.calls.enable = false;
  };
}
