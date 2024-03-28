{ config, pkgs, lib, modulesPath, ... }:
# Dell Latitude E5470
let
  cfg = config.kdn.profile.host.obler;
in
{
  options.kdn.profile.host.obler = {
    enable = lib.mkEnableOption "enable obler host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.desktop.enable = true;
      kdn.profile.hardware.dell-e5470.enable = true;
      security.sudo.wheelNeedsPassword = false;

      kdn.desktop.kde.enable = true;
      home-manager.users.root.stylix.targets.kde.enable = false;
      home-manager.users.kdn.stylix.targets.kde.enable = false;

      kdn.profile.user.sn.enable = true;

      services.teamviewer.enable = true;
      services.xserver.displayManager.sddm.settings = {
        Autologin = {
          Session = "plasma.desktop";
          User = "sn";
        };
      };

      kdn.locale = {
        primary = "pl_PL.UTF-8";
        time = "pl_PL.UTF-8";
      };

      systemd.tmpfiles.rules = [
        /*
        error:
          failed to lock /etc/exports.d/zfs.exports.lock: No such file or directory
        see:
        - https://github.com/openzfs/zfs/issues/15369
        - https://www.reddit.com/r/zfs/comments/17uf8wg/can_i_remove_an_old_entry_in/
        */
        "d /etc/exports.d 1755 root root"
      ];

      # fails on wallpaper
      systemd.services."home-manager-sn".serviceConfig = {
        Restart = "on-failure";
        RestartSec = 5;
        StartLimitBurst = 3;
        StartLimitIntervalSec = 24 * 60 * 60;
      };

      kdn.filesystems.disko.luks-zfs.enable = true;
      kdn.filesystems.disko.luks-zfs.decryptRequiresUnits = [
        "dev-bus-usb-001-002.device"
      ];
      stylix.image = pkgs.fetchurl {
        # non-expiring share link
        url = "https://nc.nazarewk.pw/s/q63pjY9H93faf5t/download/lake-view-with-light-blue-water-a6cnqa1pki4g69jt.jpg";
        sha256 = "sha256-0Dyc9Kj9IkStIJDXw9zlEFHqc2Q5WruPSk/KapM7KgM=";
      };
      stylix.polarity = "light";
      stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/standardized-light.yaml";
    }
    (import ./disko.nix { inherit lib; hostname = config.networking.hostName; })
  ]);
}
