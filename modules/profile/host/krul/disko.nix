{ lib, hostname ? "krul", inMicroVM ? false, ... }:
let
  poolName = "${hostname}-main";
  bootDevice = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04MBA03UR5RXVOGO-0:0";
  luksBackupDir = "/nazarewk-iskaral/secrets/luks/${hostname}";
  luksKeyFile = "${luksBackupDir}/luks-${poolName}-keyfile.bin";
  luksHeaderBackup = "${luksBackupDir}/luks-${poolName}-header.img";
  luksHeader = "${bootDevice}-part2";
  # uuidgen
  luksUUID = "c388dd7f-564a-4c82-a94e-85110d97d041";
  rootDevice = "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2L482L2B1Q1J";
in
{
  disk = {
    boot = {
      type = "disk";
      device = bootDevice;
      content = {
        type = "table";
        format = "gpt";
        partitions = [
          {
            name = "ESP";
            start = "1MiB";
            end = "4096MiB";
            fs-type = "fat32";
            bootable = true;
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          }
          {
            name = "${poolName}-header";
            start = "4096MiB";
            end = "4128MiB";
          }
        ];
      };
    };
    crypted-root = {
      type = "disk";
      device = rootDevice;
      content = {
        type = "luks";
        name = "${poolName}-crypted";
        keyFile = luksKeyFile;
        extraFormatArgs = [
          "--uuid=${luksUUID}"
          "--header=${luksHeader}"
          "--header-backup-file=${luksHeaderBackup}"
        ];
        extraOpenArgs = [
          "--header=${luksHeader}"
        ];
        content = {
          type = "zfs";
          pool = poolName;
        };
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
