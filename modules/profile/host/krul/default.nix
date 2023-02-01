{ config, pkgs, lib, modulesPath, self, ... }:
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
  options.kdn.profile.host.krul = {
    enable = lib.mkEnableOption "enable krul host profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.workstation.enable = true;
    kdn.hardware.gpu.amd.enable = true;

    boot.initrd.availableKernelModules = [
      "r8169" # Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] (rev 05)
      "igb" # Intel Corporation I211 Gigabit Network Connection [8086:1539] (rev 03)
    ];

    kdn.k3s.single-node.enable = false;
    kdn.k3s.single-node.enableTools = true;
    kdn.k3s.single-node.rook-ceph.enable = true;
    kdn.k3s.single-node.kube-prometheus.enable = true;
    kdn.k3s.single-node.istio.enable = true;
    kdn.k3s.single-node.zfsVolume = "nazarewk-krul-primary/nazarewk-krul/containers/containerd/io.containerd.snapshotter.v1.zfs";
    kdn.k3s.single-node.reservations.system.cpu = "4";
    kdn.k3s.single-node.reservations.system.memory = "32G";
    kdn.k3s.single-node.reservations.kube.cpu = "4";
    kdn.k3s.single-node.reservations.kube.memory = "4G";
    # kdn.containers.podman.enable = true;

    networking.interfaces.enp5s0.wakeOnLan.enable = true;
    networking.interfaces.enp6s0.wakeOnLan.enable = true;

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
      (mkZFSMount "/home/kdn" { })
      (mkZFSMount "/home/kdn/.cache" { })
      (mkZFSMount "/home/kdn/.local" { })
      (mkZFSMount "/home/kdn/.local/share" { })
      (mkZFSMount "/home/kdn/.local/share/containers" { })
      (mkZFSMount "/home/kdn/Downloads" { })
      (mkZFSMount "/home/kdn/Nextcloud" { })
    ];
    kdn.networking.netbird.instances.w1 = 51822;
  };
}
