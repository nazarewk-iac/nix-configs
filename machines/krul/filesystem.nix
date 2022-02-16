{
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;
  zramSwap.priority = 100;

  boot.tmpOnTmpfs = true;
  boot.tmpOnTmpfsSize = "10%"; # 10% of 128GB should be fine

  # legacy mountpoints
  fileSystems."/" = {
    device = "nazarewk-krul-primary/nazarewk-krul/nixos/root";
    fsType = "zfs";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2BFB-6A81";
    fsType = "vfat";
  };
  fileSystems."/etc" = {
    device = "nazarewk-krul-primary/nazarewk-krul/nixos/etc";
    fsType = "zfs";
  };
  fileSystems."/nix" = {
    device = "nazarewk-krul-primary/nazarewk-krul/nixos/nix";
    fsType = "zfs";
  };
  fileSystems."/var" = {
    device = "nazarewk-krul-primary/nazarewk-krul/nixos/var";
    fsType = "zfs";
  };
  fileSystems."/var/log" = {
    device = "nazarewk-krul-primary/nazarewk-krul/nixos/var/log";
    fsType = "zfs";
  };
  fileSystems."/var/log/journal" = {
    device = "nazarewk-krul-primary/nazarewk-krul/nixos/var/log/journal";
    fsType = "zfs";
  };
  fileSystems."/var/spool" = {
    device = "nazarewk-krul-primary/nazarewk-krul/nixos/var/spool";
    fsType = "zfs";
  };

  # ZFS mountpoints
  boot.zfs.extraPools = [
    "nazarewk-krul-primary"
  ];
}