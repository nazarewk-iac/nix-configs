{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.krul;
  hostname = config.networking.hostName;

  mkZFSMountBase =
    { path
    , at ? path
    , poolPrefix ? ""
    }: {
      "${at}" = {
        device = "${hostname}-main/${hostname}${poolPrefix}${path}";
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

  config = lib.mkIf cfg.enable ({
    kdn.desktop.kde.enable = false;
    kdn.desktop.sway.enable = true;

    kdn.profile.machine.workstation.enable = true;
    kdn.hardware.gpu.amd.enable = true;
    kdn.hardware.cpu.amd.enable = true;

    kdn.programs.photoprism.enable = false;

    services.nix-serve = {
      enable = false;
      secretKeyFile = "/var/nix-keys/krul.kdn.im/cache-priv-key.pem";
    };

    kdn.profile.machine.gaming.enable = true;

    boot.initrd.availableKernelModules = [
      "r8169" # Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] (rev 05)
      "igb" # Intel Corporation I211 Gigabit Network Connection [8086:1539] (rev 03)
    ];

    kdn.k3s.single-node.enable = false;
    kdn.k3s.single-node.enableTools = true;
    kdn.k3s.single-node.rook-ceph.enable = true;
    kdn.k3s.single-node.kube-prometheus.enable = true;
    kdn.k3s.single-node.istio.enable = true;
    kdn.k3s.single-node.zfsVolume = "krul-main/krul/containers/containerd/io.containerd.snapshotter.v1.zfs";
    kdn.k3s.single-node.reservations.system.cpu = "4";
    kdn.k3s.single-node.reservations.system.memory = "32G";
    kdn.k3s.single-node.reservations.kube.cpu = "4";
    kdn.k3s.single-node.reservations.kube.memory = "4G";

    networking.interfaces.enp5s0.wakeOnLan.enable = true;
    networking.interfaces.enp6s0.wakeOnLan.enable = true;

    zramSwap.enable = lib.mkDefault true;
    zramSwap.memoryPercent = 50;
    zramSwap.priority = 100;

    disko.enableConfig = true;
    disko.devices = import ./disko.nix {
      inherit lib;
      hostname = config.networking.hostName;
      inMicroVM = config.kdn.virtualization.microvm.guest.enable;
    };
    boot.zfs.forceImportRoot = false;
    boot.zfs.requestEncryptionCredentials = false;
    boot.initrd.luks.forceLuksSupportInInitrd = true;
    boot.kernelParams =
      let
        disko = config.disko.devices;
        crypted = disko.disk.crypted-root;
        boot = disko.disk.boot;

        getArg = name: lib.trivial.pipe crypted.content.extraFormatArgs [
          (builtins.filter (lib.strings.hasPrefix "--${name}="))
          builtins.head
          (lib.strings.removePrefix "--${name}=")
        ];

        luksOpenName = crypted.content.name;
        rootUUID = getArg "uuid";
        headerPath = getArg "header";
        luksDevice = crypted.device;
      in
      [
        # https://www.freedesktop.org/software/systemd/man/systemd-cryptsetup-generator.html#
        "rd.luks.name=${rootUUID}=${luksOpenName}"
        "rd.luks.options=${rootUUID}=header=${headerPath}"
        "rd.luks.data=${rootUUID}=${luksDevice}"

        "video=DP-1:e" # edid fix see https://gitlab.freedesktop.org/drm/amd/-/issues/615#note_1987392
      ];

    kdn.hardware.edid.enable = true;
    kdn.hardware.edid.kernelOutputs = {
      "DP-1" = "PG278Q_60";
      # "DVI-D-1" = "U2711_60";
    };

    boot.tmp.useTmpfs = true;
    # 20% of 128GB should be fine
    # 12G was not enough for large rebuild
    boot.tmp.tmpfsSize = "20%";

    # legacy mountpoints
    fileSystems = lib.mkMerge [
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
      #(mkZFSMount "/home/kdn/.local/share/containers" { })
      (mkZFSMount "/home/kdn/Downloads" { })
      (mkZFSMount "/home/kdn/Nextcloud" { })
      {
        "/boot".neededForBoot = true;
        "/var/log/journal".neededForBoot = true;
      }
    ];
  });
}
