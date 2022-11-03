{ config, lib, ... }:
let
  cfg = config.kdn.profile.host.krul;

  mkZFSMountBase =
    { path
    , at ? path
    , hostname ? config.networking.hostName
    , poolName ? "${hostname}-primary"
    , poolPrefix ? ""
    }: {
      "${at}" = {
        device = "${poolName}/${hostname}${poolPrefix}${path}";
        fsType = "zfs";
      };
    };
  mkZFSMount = path: opts: mkZFSMountBase ({ inherit path; } // opts);
  mkContainerMount = path: opts: mkZFSMountBase ({ inherit path; poolPrefix = "/containers"; } // opts);
  mkNixOSMount = path: opts: mkZFSMountBase ({ inherit path; poolPrefix = "/nixos"; } // opts);
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
    fileSystems = lib.mkMerge [
      {
        "/boot" = {
          device = "/dev/disk/by-uuid/2BFB-6A81";
          fsType = "vfat";
        };
      }
      (mkNixOSMount "/root" { at = "/"; })
      (mkNixOSMount "/etc" { })
      (mkNixOSMount "/nix" { })
      (mkNixOSMount "/var" { })
      (mkNixOSMount "/var/lib/libvirt" { })
      (mkNixOSMount "/var/lib/rook" { })
      (mkNixOSMount (config.microvm.stateDir or "/var/lib/microvms") { })
      (mkNixOSMount "/var/log" { })
      (mkNixOSMount "/var/log/journal" { })
      (mkNixOSMount "/var/spool" { })
      (mkContainerMount "/containerd" { at = "/var/lib/containerd"; })
      (mkZFSMount "/home" { })
      (mkZFSMount "/home/nazarewk" { })
      (mkZFSMount "/home/nazarewk/.cache" { })
      (mkZFSMount "/home/nazarewk/.local" { })
      (mkZFSMount "/home/nazarewk/.local/share" { })
      (mkZFSMount "/home/nazarewk/.local/share/containers" { })
      (mkZFSMount "/home/nazarewk/Downloads" { })
      (mkZFSMount "/home/nazarewk/Nextcloud" { })
    ];
  };
}
