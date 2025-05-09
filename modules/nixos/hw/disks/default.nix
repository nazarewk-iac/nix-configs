{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hw.disks;
  hostname = config.kdn.hostName;
in {
  imports = [
    ./config.nix
  ];

  config = lib.mkMerge [
    (lib.mkIf cfg.enable (lib.mkMerge [
      {
        kdn.hw.disks.base."sys/cache".snapshots = false;
        kdn.hw.disks.base."sys/config".snapshots = true;
        kdn.hw.disks.base."sys/data".snapshots = true;
        kdn.hw.disks.base."sys/reproducible".snapshots = false;
        kdn.hw.disks.base."sys/state".snapshots = false;
        kdn.hw.disks.base."usr/cache".snapshots = false;
        kdn.hw.disks.base."usr/config".snapshots = true;
        kdn.hw.disks.base."usr/data".snapshots = true;
        kdn.hw.disks.base."usr/reproducible".snapshots = false;
        kdn.hw.disks.base."usr/state".snapshots = false;
        kdn.hw.disks.userDefaults.homeLocation = lib.mkDefault "disposable";
      }
      {
        # Basic /boot config
        fileSystems."/boot".neededForBoot = true;
        kdn.hw.disks.devices."boot".type = "gpt";
        kdn.hw.disks.devices."boot".partitions."ESP" = {
          num = 1;
          size = 4096;
          disko = {
            /*
              https://uapi-group.org/specifications/specs/discoverable_partitions_specification/
            Name: EFI System Partition
            UUID: c12a7328-f81f-11d2-ba4b-00a0c93ec93b SD_GPT_ESP
            Filesystems: VFAT
            Explanation:
              The ESP used for the current boot is automatically mounted to /boot/ or /efi/,
              unless a different partition is mounted there (possibly via /etc/fstab) or
              the mount point directory is non-empty on the root disk.
              If both ESP and XBOOTLDR exist, the /efi/ mount point shall be used for ESP.
              This partition type is defined by the UEFI Specification.
            */
            type = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
            label = "ESP";
            content.type = "filesystem";
            content.format = "vfat";
            content.mountpoint = "/boot";
            content.mountOptions = [
              "fmask=0077"
              "dmask=0077"
            ];
          };
        };
      }
      {
        # zpool config
        kdn.hw.disks.zpools."${cfg.zpool-main.name}" = {};
      }
      {
        # system-wide disks
        disko.devices.zpool."${cfg.zpool-main.name}".datasets = {
          "${hostname}/nix-system/nix-store" = {
            type = "zfs_fs";
            mountpoint = "/nix/store";
            options.mountpoint = "/nix/store";
          };
          "${hostname}/nix-system/nix-var" = {
            type = "zfs_fs";
            mountpoint = "/nix/var";
            options.mountpoint = "/nix/var";
          };
        };
      }
      {
        kdn.hw.disks.persist."sys/data" = {
          directories = [
            "/var/lib/systemd"
            {
              directory = "/var/lib/private";
              mode = "0700";
            }
          ];
          files = [
            {
              file = "/etc/ssh/ssh_host_ed25519_key";
              how = "symlink";
              mode = "0600";
              inInitrd = true;
            }
            {
              file = "/etc/ssh/ssh_host_rsa_key";
              how = "symlink";
              mode = "0600";
              inInitrd = true;
            }
          ];
        };
        kdn.hw.disks.persist."sys/config" = {
          directories = [
            "/var/db/sudo/lectured"
            "/var/lib/nixos"
            "/var/lib/systemd/pstore"
            "/var/spool"
          ];
          files = [
            "/etc/printcap" # CUPS printer config
            #"/etc/subgid" # this results in file already exists
            #"/etc/subuid" # this results in file already exists
          ];
        };
      }
      (let
        baseCfg = config.kdn.hw.disks.base."sys/config";
      in {
        # see https://nix-community.github.io/preservation/examples.html#compatibility-with-systemds-conditionfirstboot
        kdn.hw.disks.persist."sys/config".files = [
          {
            file = "/etc/machine-id";
            inInitrd = true;
            how = "symlink";
            configureParent = true;
          }
        ];

        # let the service commit the transient ID to the persistent volume
        systemd.services.systemd-machine-id-commit = {
          unitConfig.ConditionPathIsMountPoint = [
            ""
            "${baseCfg.mountpoint}/etc/machine-id"
          ];
          serviceConfig.ExecStart = [
            ""
            "systemd-machine-id-setup --commit --root ${baseCfg.mountpoint}"
          ];
        };
      })
      {
        # systemd-journald related slow-starts fixups
        boot.initrd.systemd.services.systemd-journal-flush.serviceConfig.TimeoutSec = "10s";
      }
      {
        kdn.hw.disks.persist."sys/cache" = {
          directories = [
            "/var/cache"
          ];
        };
        home-manager.sharedModules = [
          {
            kdn.hw.disks.persist."sys/cache".directories = [".cache/nix"];
          }
        ];
      }
      {
        kdn.hw.disks.persist."sys/state" = {
          directories = [
            "/var/lib/systemd/coredump"
            "/var/log"
            {
              directory = "/var/log/journal";
              inInitrd = true;
            }
          ];
        };
      }
      {
        kdn.hw.disks.persist."usr/config".files = [
          "/etc/nix/netrc" # TODO: move this out
          "/etc/nix/nix.sensitive.conf" # TODO: move this out
        ];
        home-manager.sharedModules = [
          {
            kdn.hw.disks.persist."usr/data".directories = [".local/share/nix"];
          }
        ];
      }
      {
        home-manager.sharedModules = [
          {
            kdn.hw.disks.persist."usr/cache".directories = [
              "Downloads"
            ];
            kdn.hw.disks.persist."usr/data".directories = [
              "Documents"
              "Desktop"
              "Pictures"
              "Videos"
            ];
          }
        ];
      }
      {
        disko.devices.nodev = {
          "/" = {
            fsType = "tmpfs";
            mountOptions = [
              "size=${cfg.tmpfs.size}"
              "mode=755"
            ];
          };
          "/home" = {
            fsType = "tmpfs";
            mountOptions = [
              "size=${cfg.tmpfs.size}"
              "mode=755"
            ];
          };
        };
      }
      {
        # required for kdn.hw.disks.base.*.allowOther
        programs.fuse.userAllowOther = true;
      }
    ]))
  ];
}
