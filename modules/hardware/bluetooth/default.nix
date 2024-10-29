{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.bluetooth;
in
{
  options = {
    kdn.hardware.bluetooth = {
      enable = lib.mkEnableOption "bluetooth setup";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      hardware.bluetooth.enable = true;
      services.blueman.enable = true;

      environment.persistence."sys/config".directories = [
        "/var/lib/bluetooth"
      ];
    }
  ]);
}
