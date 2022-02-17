let
  mkZFSMountBase = {path, prefix ? ""}: {
    device = "nazarewk-krul-primary/nazarewk-krul${prefix}${path}";
    fsType = "zfs";
  };
  mkZFSMount = path: mkZFSMountBase { inherit path; };
  mkNixOSMount = path: mkZFSMountBase { inherit path; prefix = "/nixos"; };
in {
  zramSwap.enable = true;
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
  fileSystems."/var/log" = mkNixOSMount "/var/log";
  fileSystems."/var/log/journal" = mkNixOSMount "/var/log/journal";
  fileSystems."/var/spool" = mkNixOSMount "/var/spool";

  fileSystems."/home" = mkZFSMount "/home";
  fileSystems."/home/nazarewk" = mkZFSMount "/home/nazarewk";
  fileSystems."/home/nazarewk/.cache" = mkZFSMount "/home/nazarewk/.cache";
  fileSystems."/home/nazarewk/Downloads" = mkZFSMount "/home/nazarewk/Downloads";
  fileSystems."/home/nazarewk/Nextcloud" = mkZFSMount "/home/nazarewk/Nextcloud";
}