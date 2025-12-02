{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.nixosModules.default
  ];

  config = lib.mkMerge [
    {
      kdn.hostName = "pryll";

      system.stateVersion = "26.05";
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
      networking.hostId = "25880d1d"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
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
      kdn.disks.initrd.failureTarget = "rescue.target";
      kdn.disks.enable = true;
      kdn.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04KE345HX9EUZLSW-0:0";

      kdn.disks.luks.volumes."hs-e100-pryll" = {
        targetSpec.path = "/dev/disk/by-id/ata-HS-SSD-E100_256G_30023586951";
        uuid = "4f314bc3-6c3c-4a37-9756-5a03d286cf7b";
        headerSpec.num = 2;
      };
    }
    {
      kdn.hw.nanokvm.enable = true;
    }
  ];
}
