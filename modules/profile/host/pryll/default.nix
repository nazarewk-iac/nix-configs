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

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.hardware.cpu.intel.enable = true;
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

      kdn.locale = {
        primary = "pl_PL.UTF-8";
        time = "pl_PL.UTF-8";
      };

      # fails on wallpaper
      systemd.services."home-manager-bn".serviceConfig = {
        Restart = "on-failure";
        RestartSec = 5;
        StartLimitBurst = 3;
      };

      stylix.image = pkgs.fetchurl {
        # non-expiring share link
        url = "https://nc.nazarewk.pw/s/q63pjY9H93faf5t/download/lake-view-with-light-blue-water-a6cnqa1pki4g69jt.jpg";
        sha256 = "sha256-0Dyc9Kj9IkStIJDXw9zlEFHqc2Q5WruPSk/KapM7KgM=";
      };
      stylix.polarity = "light";
      stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/standardized-light.yaml";
    }
    {
      kdn.hardware.disks.initrd.failureTarget = "rescue.target";
      kdn.hardware.disks.enable = true;
      kdn.hardware.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04KE345HX9EUZLSW-0:0";

      kdn.hardware.disks.luks.volumes."hs-e100-pryll" = {
        targetSpec.path = "/dev/disk/by-id/ata-HS-SSD-E100_256G_30023586951";
        uuid = "4f314bc3-6c3c-4a37-9756-5a03d286cf7b";
        headerSpec.num = 2;
      };
    }
    {
      kdn.hardware.nanokvm.enable = true;
    }
  ]);
}
