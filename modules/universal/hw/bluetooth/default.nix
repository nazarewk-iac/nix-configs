{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.hw.bluetooth;
in
{
  options = {
    kdn.hw.bluetooth = {
      enable = lib.mkEnableOption "bluetooth setup";
    };
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          hardware.bluetooth.enable = true;
          services.blueman.enable = true;

          kdn.disks.persist."sys/config".directories = [
            "/var/lib/bluetooth"
          ];
        }
      ]
    )
  );
}
