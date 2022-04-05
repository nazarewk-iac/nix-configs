{ lib, ... }:
let
  mkZFSMountBase = {path, prefix ? ""}: {
    device = "nazarewk-krul-primary/nazarewk-krul${prefix}${path}";
    fsType = "zfs";
  };
  mkZFSMount = path: mkZFSMountBase { inherit path; };
  mkContainerMount = path: mkZFSMountBase { inherit path; prefix = "/containers"; };
  mkNixOSMount = path: mkZFSMountBase { inherit path; prefix = "/nixos"; };
in {
  zramSwap.enable = lib.mkDefault true;
  zramSwap.memoryPercent = 50;
  zramSwap.priority = 100;

  boot.tmpOnTmpfs = true;
  boot.tmpOnTmpfsSize = "10%"; # 10% of 128GB should be fine

  # legacy mountpoints
  fileSystems."/" = mkNixOSMount "/root";
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2BFB-6A81";
    fsType = "vfat";
  };
  fileSystems."/etc" = mkNixOSMount "/etc";
  fileSystems."/nix" = mkNixOSMount "/nix";
  fileSystems."/var" = mkNixOSMount "/var";
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

#  environment.etc.crypttab.enable = false;  # the partition got removed
#  environment.etc.crypttab.text = ''
#  # /dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2L482L2B1Q1J-part3
#  #rook-ceph-nvme-0 UUID=3c8fbcf0-3394-495a-b7a3-a162f8a942f9 /var/lib/rook/nvme-XPG_GAMMIX_S70_BLADE_2L482L2B1Q1J-part3.key
#  '';
}
