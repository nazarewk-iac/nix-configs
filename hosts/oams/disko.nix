{
  lib,
  hostname ? "oams",
  bootDevice ? "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04S631EMZERE01LQ-0:0",
  #, bootDevice ? "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04UER08H5B7Y0NA5-0:0"
  # uuidgen
  luksUUID ? "c4b9bdbc-900f-482e-8fa6-6c6824c560e9",
  rootDevice ? "/dev/disk/by-id/nvme-eui.00000000000000016479a723dac0001d",
  backupDir ? "/nazarewk-iskaral/secrets/luks",
  ...
}: let
  poolName = "${hostname}-main";
  bootPartition = "${bootDevice}-part1";
  luksBackupDir = "${backupDir}/${hostname}";
  luksKeyFile = "${luksBackupDir}/luks-${poolName}-keyfile.bin";
  luksHeaderBackup = "${luksBackupDir}/luks-${poolName}-header.img";
  luksHeaderPartition = "${bootDevice}-part2";
in {
  disko.devices = {
    disk.boot = {
      type = "disk";
      device = bootDevice;
      content = {
        type = "gpt";
        partitions.ESP = {
          device = bootPartition;
          start = "1MiB";
          end = "4096MiB";
          # see https://en.wikipedia.org/wiki/GUID_Partition_Table#Partition_type_GUIDs
          # EFI System partition 	C12A7328-F81F-11D2-BA4B-00A0C93EC93B
          type = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        partitions."${poolName}-header" = {
          device = luksHeaderPartition;
          start = "4096MiB";
          end = "4128MiB";
          type = "00000000-0000-0000-0000-000000000000";
        };
      };
    };
    disk.crypted-root = {
      type = "disk";
      device = rootDevice;
      content = {
        type = "luks";
        name = "${poolName}-crypted-0";
        settings.crypttabExtraOpts = ["fido2-device=auto"];
        settings.header = luksHeaderPartition;
        additionalKeyFiles = [luksKeyFile];
        extraFormatArgs = [
          "--uuid=${luksUUID}"
          "--header=${luksHeaderPartition}"
          "--header-backup-file=${luksHeaderBackup}"
        ];
        extraOpenArgs = [
          "--header=${luksHeaderPartition}"
        ];
        content = {
          type = "zfs";
          pool = poolName;
        };
      };
    };

    zpool."${poolName}" = {
      type = "zpool";
      name = poolName;
      rootFsOptions = {
        acltype = "posixacl";
        relatime = "on";
        xattr = "sa";
        dnodesize = "auto";
        normalization = "formD";
        mountpoint = "none";
        canmount = "off";
        devices = "off";
        compression = "lz4";
        "com.sun:auto-snapshot" = "false";
      };

      options = {
        ashift = "12";
        "feature@large_dnode" = "enabled"; # required by dnodesize!=legacy
      };

      datasets = let
        snapOn = {
          options."com.sun:auto-snapshot" = "true";
        };
        snapOff = {
          options."com.sun:auto-snapshot" = "false";
        };
        fs = {
          type = "zfs_fs";
        };

        ds = mp: patches:
          lib.foldl lib.recursiveUpdate {} (
            [fs]
            ++ patches
            ++ [
              {
                mountpoint = mp;
                options.mountpoint = mp;
              }
            ]
          );
      in {
        "fs/root" = ds "/root" [snapOn];
        "fs/etc" = ds "/etc" [snapOn];
        "fs/home" = ds "/home" [snapOn];
        "fs/home/kdn" = ds "/home/kdn" [];
        "fs/home/kdn/.cache" = ds "/home/kdn/.cache" [snapOff];
        "fs/home/kdn/.config" = ds "/home/kdn/.config" [];
        "fs/home/kdn/.local" = ds "/home/kdn/.local" [];
        "fs/home/kdn/.local/share" = ds "/home/kdn/.local/share" [];
        "fs/home/kdn/.local/share/containers" = ds "/home/kdn/.local/share/containers" [snapOff];
        "fs/home/kdn/.local/share/Steam" = ds "/home/kdn/.local/share/Steam" [snapOff];
        "fs/home/kdn/.local/share/Steam/steamapps" = ds "/home/kdn/.local/share/Steam/steamapps" [];
        "fs/home/kdn/.local/share/Steam/steamapps/common" =
          ds "/home/kdn/.local/share/Steam/steamapps/common"
          [];
        "fs/home/kdn/Downloads" = ds "/home/kdn/Downloads" [snapOff];
        "fs/home/kdn/Nextcloud" = ds "/home/kdn/Nextcloud" [snapOff];
        "fs/home/kdn/dev" = ds "/home/kdn/dev" [];
        "fs/nix" = ds "/nix" [];
        "fs/nix/store" = ds "/nix/store" [
          snapOff
          {options.atime = "off";}
        ];
        "fs/nix/var" = ds "/nix/var" [
          snapOff
          {
            options."com.sun:auto-snapshot" = "false";
            options.compression = "off";
            options.atime = "off";
            options.redundant_metadata = "none";
            options.sync = "disabled";
          }
        ];
        "fs/var" = ds "/var" [snapOn];
        "fs/var/lib" = ds "/var/lib" [];
        "fs/var/lib/libvirt" = ds "/var/lib/libvirt" [];
        "fs/var/lib/microvms" = ds "/var/lib/microvms" [];
        "fs/var/lib/nixos" = ds "/var/lib/nixos" [];
        "fs/var/log" = ds "/var/log" [snapOff];
        "fs/var/log/journal" = ds "/var/log/journal" [];
        "fs/var/spool" = ds "/var/spool" [];
      };
    };
    nodev = {
      "/" = {
        fsType = "tmpfs";
        mountOptions = [
          "size=32M"
          "mode=755"
        ];
      };
    };
  };
}
