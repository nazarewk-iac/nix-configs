{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.profile.machine.basic;
in
{
  options.kdn.profile.machine.basic = {
    enable = lib.mkEnableOption "basic machine profile for interactive use";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.baseline.enable = true;
      kdn.programs.gnupg.enable = true;

      networking.networkmanager.wifi.powersave = true;

      boot.loader.systemd-boot.memtest86.enable = true;

      # HARDWARE
      hardware.usb-modeswitch.enable = true;
      environment.systemPackages = with pkgs; [ usb-modeswitch ];
      kdn.hardware.bluetooth.enable = true;

      documentation.man.man-db.enable = lib.mkDefault true;
      documentation.man.generateCaches = lib.mkDefault true;
    }
    {
      environment.systemPackages = with pkgs; [
        lsix # image thumbnails in terminal
      ];
    }
    (lib.mkIf config.boot.initrd.systemd.enable {
      specialisation.debug = {
        inheritParentConfig = true;
        configuration = {
          system.nixos.tags = [ "debug" ];
          boot.kernelParams = [
            # see https://www.thegeekdiary.com/how-to-debug-systemd-boot-process-in-centos-rhel-7-and-8-2/
            #"systemd.confirm_spawn=true"  # this seems to ask and times out before executing anything during boot
            "systemd.debug-shell=1"
            "systemd.log_level=debug"
          ];
        };
      };
      specialisation.rescue = {
        inheritParentConfig = true;
        configuration = {
          system.nixos.tags = [ "rescue" ];
          systemd.defaultUnit = lib.mkForce "rescue.target";
          boot.kernelParams = [
            # see https://www.thegeekdiary.com/how-to-debug-systemd-boot-process-in-centos-rhel-7-and-8-2/
            #"systemd.confirm_spawn=true"  # this seems to ask and times out before executing anything during boot
            "systemd.debug-shell=1"
            "systemd.log_level=debug"
          ];
        };
      };
    })
  ]);
}
