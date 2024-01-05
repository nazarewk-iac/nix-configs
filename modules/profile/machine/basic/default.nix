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
    kdn.programs.gnupg.enable = true;

    services.avahi.enable = true;
    networking.networkmanager.wifi.powersave = true;

    boot.loader.systemd-boot.memtest86.enable = true;

    # HARDWARE
    hardware.usb-modeswitch.enable = true;
    environment.systemPackages = with pkgs; [ usb-modeswitch ];
    hardware.bluetooth.enable = true;
    services.blueman.enable = true;

    home-manager.sharedModules = [{ xdg.userDirs.enable = true; }];
  };
}
