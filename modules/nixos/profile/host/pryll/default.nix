{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.profile.host.pryll;
in {
  options.kdn.profile.host.pryll = {
    enable = lib.mkEnableOption "enable pryll host profile";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.hw.cpu.intel.enable = true;
        kdn.hw.gpu.intel.enable = true;
        kdn.profile.machine.desktop.enable = true;
        security.sudo.wheelNeedsPassword = false;
      }
      {
        kdn.desktop.kde.enable = true;
        home-manager.users.root.stylix.targets.kde.enable = false;
        home-manager.users.kdn.stylix.targets.kde.enable = false;

        services.teamviewer.enable = true;
      }
      {
        kdn.profile.user.bn.enable = true;
        services.displayManager.sddm.settings = {
          Autologin = {
            Session = "plasma.desktop";
            User = "bn";
          };
        };

        # fails on wallpaper
        systemd.services."home-manager-bn".serviceConfig = {
          Restart = "on-failure";
          RestartSec = 5;
          StartLimitBurst = 3;
        };
      }
      {
        kdn.hw.disks.initrd.failureTarget = "rescue.target";
        kdn.hw.disks.enable = true;
        kdn.hw.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04KE345HX9EUZLSW-0:0";

        kdn.hw.disks.luks.volumes."hs-e100-pryll" = {
          targetSpec.path = "/dev/disk/by-id/ata-HS-SSD-E100_256G_30023586951";
          uuid = "4f314bc3-6c3c-4a37-9756-5a03d286cf7b";
          headerSpec.num = 2;
        };
      }
      {
        kdn.hw.nanokvm.enable = true;
      }
    ]
  );
}
