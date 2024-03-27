{ lib
, hostname ? "krul"
, bootDevice ? "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04MBA03UR5RXVOGO-0:0"
  # uuidgen
, luksUUID ? "c388dd7f-564a-4c82-a94e-85110d97d041"
, rootDevice ? "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2L482L2B1Q1J"
, backupDir ? "/nazarewk-iskaral/secrets/luks"
, inMicroVM ? false
, ...
}:
let
  poolName = "${hostname}-main";
  bootPartition = "${bootDevice}-part1";
  luksBackupDir = "${backupDir}/${hostname}";
  luksKeyFile = "${luksBackupDir}/luks-${poolName}-keyfile.bin";
  luksHeaderBackup = "${luksBackupDir}/luks-${poolName}-header.img";
  luksHeaderPartition = "${bootDevice}-part2";
in
{
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
      settings.crypttabExtraOpts = [ "fido2-device=auto" ];
      additionalKeyFiles = [ luksKeyFile ];
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
    datasets = { };
  };
}
