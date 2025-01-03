{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hardware.disks;
  hostname = config.networking.hostName;

  sysCfg = lib.attrsets.recursiveUpdate {imp.enableActivationScript = true;};
in {
  config = lib.mkMerge [
    (lib.mkIf cfg.enable (lib.mkMerge [
      {
        impermanence.userDefaultPerms.mode = "0700";
        impermanence.defaultPerms.mode = "0750";

        environment.persistence = lib.pipe cfg.impermanence [
          (builtins.mapAttrs (name: _: {
            enableActivationScript = lib.mkDefault (lib.strings.hasPrefix "sys/" name);
          }))
        ];

        kdn.hardware.disks.impermanence."sys/cache".snapshots = false;
        kdn.hardware.disks.impermanence."sys/config".snapshots = true;
        kdn.hardware.disks.impermanence."sys/data".snapshots = true;
        kdn.hardware.disks.impermanence."sys/reproducible".snapshots = false;
        kdn.hardware.disks.impermanence."sys/state".neededForBoot = ["/var/log/journal"];
        kdn.hardware.disks.impermanence."sys/state".snapshots = false;
        kdn.hardware.disks.impermanence."usr/cache".snapshots = false;
        kdn.hardware.disks.impermanence."usr/config".snapshots = true;
        kdn.hardware.disks.impermanence."usr/data".snapshots = true;
        kdn.hardware.disks.impermanence."usr/reproducible".snapshots = false;
        kdn.hardware.disks.impermanence."usr/state".snapshots = false;
        kdn.hardware.disks.userDefaults.homeLocation = lib.mkDefault "disposable";
      }
      {
        # Basic /boot config
        fileSystems."/boot".neededForBoot = true;
        kdn.hardware.disks.devices."boot".type = "gpt";
        kdn.hardware.disks.devices."boot".partitions."ESP" = {
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
        kdn.hardware.disks.zpools."${cfg.zpool-main.name}" = {};
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
        environment.persistence."sys/data" = {
          directories = [
            "/var/lib/systemd"
            {
              directory = "/var/lib/private";
              mode = "0700";
            }
          ];
          files = [
            "/etc/ssh/ssh_host_ed25519_key"
            "/etc/ssh/ssh_host_ed25519_key.pub"
            "/etc/ssh/ssh_host_rsa_key"
            "/etc/ssh/ssh_host_rsa_key.pub"
          ];
        };
        environment.persistence."sys/config" = {
          directories = [
            "/var/db/sudo/lectured"
            "/var/lib/nixos"
            "/var/lib/systemd/pstore"
            "/var/spool"
          ];
          files = [
            "/etc/machine-id"
            "/etc/printcap" # CUPS printer config
            #"/etc/subgid" # this results in file already exists
            #"/etc/subuid" # this results in file already exists
          ];
        };
        /*
        $ journalctl -b0 -u systemd-machine-id-commit
        Nov 05 09:40:41 etra systemd[1]: Starting Save Transient machine-id to Disk...
        Nov 05 09:40:48 etra systemd-machine-id-setup[439037]: /etc/machine-id is not on a temporary file system.
        Nov 05 09:40:48 etra systemd[1]: systemd-machine-id-commit.service: Main process exited, code=exited, status=1/FAILURE

        see discussion at https://github.com/nix-community/impermanence/issues/229
        */
        boot.initrd.systemd.suppressedUnits = ["systemd-machine-id-commit.service"];
        systemd.suppressedSystemUnits = ["systemd-machine-id-commit.service"];
      }
      {
        # systemd-journald related slow-starts fixups
        boot.initrd.systemd.services.systemd-journal-flush.serviceConfig.TimeoutSec = "10s";
      }
      {
        environment.persistence."sys/cache" = {
          directories = [
            "/var/cache"
          ];
        };
        home-manager.sharedModules = [
          {
            home.persistence."sys/cache".directories = [".cache/nix"];
          }
        ];
      }
      {
        kdn.hardware.disks.impermanence."sys/state".neededForBoot = [
          "/var/log/journal"
        ];
        environment.persistence."sys/state" = {
          directories = [
            "/var/lib/systemd/coredump"
            "/var/log"
            "/var/log/journal"
          ];
        };
      }
      {
        environment.persistence."usr/config" = {
          files = [
            "/etc/nix/netrc" # TODO: move this out
            "/etc/nix/nix.sensitive.conf" # TODO: move this out
          ];
        };
      }
      {
        home-manager.sharedModules = [
          {
            home.persistence."usr/data".directories = [".local/share/nix"];
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
        # required for home.persistence.*.allowOther
        programs.fuse.userAllowOther = true;
      }
    ]))
  ];
}
