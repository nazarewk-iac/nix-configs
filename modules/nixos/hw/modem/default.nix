{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hw.modem;
in {
  options.kdn.hw.modem = {
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
