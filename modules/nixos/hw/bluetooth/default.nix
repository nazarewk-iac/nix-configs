{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hw.bluetooth;
in {
  options = {
    kdn.hw.bluetooth = {
      enable = lib.mkEnableOption "bluetooth setup";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        hardware.bluetooth.enable = true;
        services.blueman.enable = true;

        kdn.disks.persist."sys/config".directories = [
          "/var/lib/bluetooth"
        ];
      }
    ]
  );
}
