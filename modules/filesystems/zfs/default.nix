{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.filesystems.zfs;
in
{
  options.kdn.filesystems.zfs = {
    enable = lib.mkEnableOption "ZFS setup";
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages = pkgs.zfs.latestCompatibleLinuxPackages;
    boot.loader.grub.copyKernels = true;
    boot.kernelParams = [ "nohibernate" ];
    boot.initrd.supportedFilesystems = [ "zfs" ];
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.enableUnstable = true;

    # see https://github.com/NixOS/nixpkgs/issues/169457
    boot.kernelPatches = [{
      name = "enable RT_FULL";
      patch = null;
      extraConfig = ''
        PREEMPT y
        PREEMPT_BUILD y
        PREEMPT_VOLUNTARY n
        PREEMPT_COUNT y
        PREEMPTION y
      '';
    }];

    services.zfs.autoScrub.enable = true;
    services.zfs.autoSnapshot.enable = true;
    services.zfs.autoSnapshot.flags = "-k -p --utc";
    services.zfs.autoSnapshot.frequent = 12;
    services.zfs.autoSnapshot.daily = 7;
    services.zfs.autoSnapshot.weekly = 6;
    services.zfs.autoSnapshot.monthly = 1;
    services.zfs.trim.enable = true;

    environment.systemPackages = with pkgs; [
      zfs-prune-snapshots
    ];

    virtualisation.docker.storageDriver = "zfs";
  };
}
