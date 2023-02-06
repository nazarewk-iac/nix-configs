{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.profile.machine.basic;
in
{
  options.kdn.profile.machine.basic = {
    enable = lib.mkEnableOption "enable basic machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.baseline.enable = true;

    networking.networkmanager.wifi.powersave = true;

    boot.loader.systemd-boot.memtest86.enable = true;

    # HARDWARE
    hardware.bluetooth.enable = true;
    services.blueman.enable = true;

    home-manager.sharedModules = [
      ({ config, ... }: {
        xdg.userDirs.enable = true;
      })
    ];
  };
}
