{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.filesystems.zfs;
in {
  options.nazarewk.filesystems.zfs = {
    enable = mkEnableOption "ZFS setup";
  };

  config = mkIf cfg.enable {
      boot.kernelPackages = pkgs.zfs.latestCompatibleLinuxPackages;
      boot.loader.grub.copyKernels = true;
      boot.kernelParams = [ "nohibernate" ];
      boot.initrd.supportedFilesystems = [ "zfs" ];
      boot.supportedFilesystems = [ "zfs" ];
      boot.zfs.enableUnstable = true;

      services.zfs.autoScrub.enable = true;
      services.zfs.autoSnapshot.enable = true;
      services.zfs.autoSnapshot.flags = "-k -p --utc";
      services.zfs.autoSnapshot.frequent = 12;
      services.zfs.autoSnapshot.daily = 7;
      services.zfs.autoSnapshot.weekly = 6;
      services.zfs.autoSnapshot.monthly = 1;
      services.zfs.trim.enable = true;

      virtualisation.docker.storageDriver = "zfs";
  };
}