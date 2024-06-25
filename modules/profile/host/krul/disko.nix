{ lib
, hostname ? "krul"
, bootDevice ? "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04MBA03UR5RXVOGO-0:0"
  # uuidgen
, luksUUID ? "c388dd7f-564a-4c82-a94e-85110d97d041"
  # this got changed after bios update
, rootDevice ? "/dev/disk/by-id/nvme-nvme.1dbe-5353442d35323336-4d4e2d35323336-00000001"
  #, rootDevice ? "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2L482L2B1Q1J"
, backupDir ? "/nazarewk-iskaral/secrets/luks"
, ...
}:
let
  poolName = "${hostname}-main";
  bootPartition = "${bootDevice}-part1";
  luksBackupDir = "${backupDir}/${hostname}";
  luksKeyFiles = [
    "${luksBackupDir}/luks-${poolName}-keyfile.bin"
    "${luksBackupDir}/luks-${poolName}-keyfile.clevis.bin"
  ];
  luksHeaderBackup = "${luksBackupDir}/luks-${poolName}-header.img";
  luksHeaderPartition = "${bootDevice}-part2";
in
{
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
        name = "${poolName}-crypted";
        settings.keyFile = "/clevis-${poolName}-crypted/decrypted";
        settings.header = luksHeaderPartition;
        settings.crypttabExtraOpts = [ ];
        additionalKeyFiles = luksKeyFiles;
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
      datasets =
        let
          snapOn = { options."com.sun:auto-snapshot" = "true"; };
          snapOff = { options."com.sun:auto-snapshot" = "false"; };
          fs = { type = "zfs_fs"; };

          ds = mp: patches: lib.foldl lib.recursiveUpdate { } ([ fs ] ++ patches ++ [{
            mountpoint = mp;
            options.mountpoint = mp;
          }]);
        in
        {
          "${hostname}/root" = ds "/root" [ ];
          "${hostname}/home" = ds "/home" [ snapOn ];
          "${hostname}/home/kdn" = ds "/home/kdn" [ ];
          "${hostname}/home/kdn/.cache" = ds "/home/kdn/.cache" [ snapOff ];
          "${hostname}/home/kdn/.local" = ds "/home/kdn/.local" [ ];
          "${hostname}/home/kdn/.local/share" = ds "/home/kdn/.local/share" [ ];
          "${hostname}/home/kdn/Downloads" = ds "/home/kdn/Downloads" [ snapOff ];
          "${hostname}/home/kdn/Nextcloud" = ds "/home/kdn/Nextcloud" [ snapOff ];
          "${hostname}/nixos/etc" = ds "/etc" [ snapOn ];
          "${hostname}/nixos/nix" = ds "/nix" [ ];
          "${hostname}/nixos/root" = ds "/obler-main/${hostname}/nixos/root" [ ];
          "${hostname}/nixos/var" = ds "/var" [ snapOn ];
          "${hostname}/nixos/var/lib/libvirt" = ds "/var/lib/libvirt" [ ];
          "${hostname}/nixos/var/lib/microvms" = ds "/var/lib/microvms" [ ];
          "${hostname}/nixos/var/lib/rook" = ds "/var/lib/rook" [ ];
          "${hostname}/nixos/var/log" = ds "/var/log" [ snapOff ];
          "${hostname}/nixos/var/log/journal" = ds "/var/log/journal" [ ];
          "${hostname}/nixos/var/spool" = ds "/var/spool" [ ];
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
