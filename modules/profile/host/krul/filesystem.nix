{ config, lib, ... }:
let
  cfg = config.kdn.profile.host.krul;

  mkZFSMountBase = { path, prefix ? "" }: {
    device = "nazarewk-krul-primary/nazarewk-krul${prefix}${path}";
    fsType = "zfs";
  };
  mkZFSMount = path: mkZFSMountBase { inherit path; };
  mkContainerMount = path: mkZFSMountBase { inherit path; prefix = "/containers"; };
  mkNixOSMount = path: mkZFSMountBase { inherit path; prefix = "/nixos"; };
in
{
  config = lib.mkIf cfg.enable {
    kdn.filesystems.zfs-root.enable = true;
    kdn.filesystems.zfs-root.sshUnlock.enable = true;

    zramSwap.enable = lib.mkDefault true;
    zramSwap.memoryPercent = 50;
    zramSwap.priority = 100;

    boot.zfs.requestEncryptionCredentials = [
      "nazarewk-krul-primary"
    ];

    boot.tmpOnTmpfs = true;
    # 20% of 128GB should be fine
    # 12G was not enough for large rebuild
    boot.tmpOnTmpfsSize = "20%";

    # legacy mountpoints
    fileSystems."/" = mkNixOSMount "/root";
    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/2BFB-6A81";
      fsType = "vfat";
    };
    fileSystems."/etc" = mkNixOSMount "/etc";
    fileSystems."/nix" = mkNixOSMount "/nix";
    fileSystems."/var" = mkNixOSMount "/var";
    fileSystems."/var/lib/libvirt" = mkNixOSMount "/var/lib/libvirt";
    fileSystems."/var/lib/rook" = mkNixOSMount "/var/lib/rook";
    fileSystems."/var/log" = mkNixOSMount "/var/log";
    fileSystems."/var/log/journal" = mkNixOSMount "/var/log/journal";
    fileSystems."/var/spool" = mkNixOSMount "/var/spool";

    fileSystems."/var/lib/containerd" = mkContainerMount "/containerd";

    fileSystems."/home" = mkZFSMount "/home";
    fileSystems."/home/nazarewk" = mkZFSMount "/home/nazarewk";
    fileSystems."/home/nazarewk/.cache" = mkZFSMount "/home/nazarewk/.cache";
    fileSystems."/home/nazarewk/Downloads" = mkZFSMount "/home/nazarewk/Downloads";
    fileSystems."/home/nazarewk/Nextcloud" = mkZFSMount "/home/nazarewk/Nextcloud";
  };
}