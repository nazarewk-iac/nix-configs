{ lib, hostname ? "obler", inMicroVM ? false, ... }:
let
  poolName = "${hostname}-main";
  bootDevice = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04LZCR91M8UZPJW8-0:0";
  luksBackupDir = "/nazarewk-iskaral/secrets/luks/${hostname}";
  #luksKeyFile = "${luksBackupDir}/luks-${poolName}-keyfile.bin";
  # can be copied automatically using nixos-anywhere with: --disk-encryption-keys /keyfile.bin <(sudo cat /nazarewk-iskaral/secrets/luks/obler/luks-keyfile.bin)
  luksKeyFile = "/keyfile.bin";
  luksHeaderBackup = "${luksBackupDir}/luks-${poolName}-header.img";
  luksHeader = "${bootDevice}-part2";
  luksUUID = "4971c81f-df4d-408c-a704-271b3423e762";
  rootDevice = "/dev/disk/by-id/nvme-CX2-8B256-Q11_NVMe_LITEON_256GB_TW09F8D155085668010W";
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
          #"--header-backup-file=${luksHeaderBackup}"
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

    datasets =
      let
        filesystemPrefix = "fs";
        snapshotsOn = { options."com.sun:auto-snapshot" = "true"; };
        snapshotsOff = { options."com.sun:auto-snapshot" = "false"; };
        mounts = {
          "/" = { };
          "/etc" = { } // snapshotsOn;
          "/home" = { } // snapshotsOn;
          "/home/kdn" = { };
          "/home/kdn/.cache" = { } // snapshotsOff;
          "/home/sn" = { };
          "/home/sn/.cache" = { } // snapshotsOff;
          "/home/sn/.config" = { };
          "/home/sn/.local" = { };
          "/home/sn/Downloads" = { } // snapshotsOff;
          "/nix" = { };
          "/nix/store" = { };
          "/nix/var" = { };
          "/usr" = { };
          "/var" = { } // snapshotsOn;
          "/var/lib" = { };
          "/var/lib/nixos" = { };
          "/var/log" = { } // snapshotsOff;
          "/var/log/journal" = { };
          "/var/spool" = { };
        };
      in
      lib.trivial.pipe mounts [
        (lib.attrsets.filterAttrs (n: v: !(n == "/nix/store" && inMicroVM)))
        (lib.attrsets.mapAttrs'
          (mp: cfg:
            let
              mountpoint = cfg.options.mountpoint or cfg.mountpoint or mp;
            in
            {
              name = (lib.trivial.pipe mp [
                (p: "${cfg.prefix or filesystemPrefix}${p}")
                (lib.strings.removeSuffix "/")
              ]);
              value = ({
                type = "zfs_fs";
                mountpoint = if mountpoint != "none" then mountpoint else null;

                # note: disko handles non-legacy mountpoints with `-o zfsutil` mount option
                options = { mountpoint = if mountpoint != null then mountpoint else "none"; } // cfg.options or { };
              } // (builtins.removeAttrs cfg [ "prefix" "options" ]));
            }))
      ];
  };
}
