{
  lib,
  pkgs,
  config,
  options,
  ...
}: let
  cfg = config.kdn.disks;
  hostname = config.kdn.hostName;
in {
  imports = [
    ./config.nix
  ];

  config = lib.mkMerge [
    (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.disks.base."sys/cache".snapshots = false;
          kdn.disks.base."sys/config".snapshots = true;
          kdn.disks.base."sys/data".snapshots = true;
          kdn.disks.base."sys/reproducible".snapshots = false;
          kdn.disks.base."sys/state".snapshots = false;
          kdn.disks.base."usr/cache".snapshots = false;
          kdn.disks.base."usr/config".snapshots = true;
          kdn.disks.base."usr/data".snapshots = true;
          kdn.disks.base."usr/reproducible".snapshots = false;
          kdn.disks.base."usr/state".snapshots = false;
          kdn.disks.userDefaults.homeLocation = lib.mkDefault "disposable";
        }
        {
          # Basic /boot config
          fileSystems."/boot".neededForBoot = true;
          kdn.disks.devices."${cfg.defaults.bootDeviceName}" = {
            type = "gpt";
            partitions."ESP" = {
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
          };
        }
        {
          # zpool config
          kdn.disks.zpools."${cfg.zpool-main.name}" = {};
        }
        {
          # system-wide disks
          disko.devices.zpool."${cfg.zpool-main.name}".datasets = {
            "${hostname}/nix-system/nix-store" = {
              type = "zfs_fs";
              mountpoint = "/nix/store";
              options.mountpoint = "/nix/store";
              options.atime = "off";
            };
            "${hostname}/nix-system/nix-var" = {
              type = "zfs_fs";
              mountpoint = "/nix/var";
              options.mountpoint = "/nix/var";
            };
          };
        }
        {
          kdn.disks.persist."sys/data" = {
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
          kdn.disks.persist."sys/config" = {
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
        {
          # see https://github.com/nix-community/preservation/pull/23
          kdn.disks.persist."sys/config".files = [
            {
              file = "/etc/machine-id";
              inInitrd = true;
              configureParent = true;
            }
          ];
          systemd.services.systemd-machine-id-commit.unitConfig.ConditionFirstBoot = true;
        }
        {
          # systemd-journald related slow-starts fixups
          boot.initrd.systemd.services.systemd-journal-flush.serviceConfig.TimeoutSec = "10s";
        }
        {
          kdn.disks.persist."sys/cache" = {
            directories = [
              "/var/cache"
            ];
          };
          home-manager.sharedModules = [
            {
              kdn.disks.persist."sys/cache".directories = [".cache/nix"];
            }
          ];
        }
        {
          kdn.disks.persist."sys/state" = {
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
          kdn.disks.persist."usr/config".files = [
            "/etc/nix/netrc" # TODO: move this out
            "/etc/nix/nix.sensitive.conf" # TODO: move this out
          ];
          home-manager.sharedModules = [
            {
              kdn.disks.persist."usr/data".directories = [".local/share/nix"];
            }
          ];
        }
        {
          home-manager.sharedModules = [
            {
              kdn.disks.persist."usr/cache".directories = [
                "Downloads"
              ];
              kdn.disks.persist."usr/data".directories = [
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
        # WARNING: keep build dir in sync with /modules/universal/nix.nix
        # throws recursion error if tries to be derived from `config.nix.settings.build-dir`
        # TODO: mount those at different places to make them easily swappable?
        {
          systemd.tmpfiles.rules = [
            "L+ /nix/var/nix/builds           - - - - /nix/var/nix/builds-${cfg.nixBuildDir.type}"
          ];
          kdn.disks.persist."disposable".directories = [
            {
              # see https://github.com/NixOS/nix/blob/bbd14173b5c4677d098686be9605c88b40149684/doc/manual/source/release-notes/rl-2.30.md?plain=1#L5-L11
              # it could also be in `config.nix.extraOptions`, but let's not bother with that
              directory = "/nix/var/nix/builds-disposable";
              mode = "0755";
            }
          ];
          disko.devices.nodev."/nix/var/nix/builds-tmpfs" = {
            fsType = "tmpfs";
            mountOptions = [
              "size=${cfg.nixBuildDir.tmpfs.size}"
              "mode=755"
            ];
          };
          # system-wide disks
          disko.devices.zpool."${cfg.zpool-main.name}".datasets = {
            /*
            TODO: adjust according to recommendations from Matrix https://matrix.to/#/!6oudZq5zJjAyrxL2uY:0upti.me/$4QbeVc0OKEQtQYrnBDn7VzolWR6AoSPQ0LqPVDtEgD0?via=laas.fr&via=matrix.org&via=node.marinchik.ink
              for build dirs:
              - debatable about compression. it's normally fine and cheap, but does use cpu and in this case right when you want the cpu for something else. depends heavily on other aspects of the system
              - consider sync=disabled
              - consider redundant_metadata=some or none, for disposable datasets, to cut down on sync iops
              - you already have relatime, good.. but consider if you need atime at all

            the creation command:
            > zfs create -u briv-main/briv/nix-system/nix-builds -o mountpoint=/nix/var/nix/builds-zfs-dataset -o atime=off -o redundant_metadata=none -o sync=disabled -o com.sun:auto-snapshot=false -o compression=off

            WARNING: might need to run it on each affected host:
            - briv
            */
            "${hostname}/nix-system/nix-builds" = {
              type = "zfs_fs";
              mountpoint = "/nix/var/nix/builds-zfs-dataset";
              options.mountpoint = "/nix/var/nix/builds-zfs-dataset";
              options."com.sun:auto-snapshot" = "false";
              options.compression = "off";
              options.atime = "off";
              options.redundant_metadata = "none";
              options.sync = "disabled";
            };
          };
        }
        {
          # required for kdn.disks.base.*.allowOther
          programs.fuse.userAllowOther = true;
        }
      ]
    ))
    {
      kdn.disks.disko.devices._meta = options.disko.devices.valueMeta.configuration.options._meta.default;
      disko.devices._meta = config.kdn.disks.disko.devices._meta;
    }
  ];
}
