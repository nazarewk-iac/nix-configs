{ lib
, hostname ? "oams"
, bootDevice ? "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04S631EMZERE01LQ-0:0"
  #, bootDevice ? "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04UER08H5B7Y0NA5-0:0"
  # uuidgen
, luksUUID ? "c4b9bdbc-900f-482e-8fa6-6c6824c560e9"
, rootDevice ? "/dev/disk/by-id/nvme-eui.00000000000000016479a723dac0001d"
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
      name = "${poolName}-crypted-0";
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
          "/home/kdn/.config" = { };
          "/home/kdn/.local" = { };
          "/home/kdn/.local/share" = { };
          "/home/kdn/.local/share/containers" = { } // snapshotsOff;
          "/home/kdn/.local/share/Steam" = { } // snapshotsOff;
          "/home/kdn/.local/share/Steam/steamapps" = { };
          "/home/kdn/.local/share/Steam/steamapps/common" = { };
          "/home/kdn/Downloads" = { } // snapshotsOff;
          "/home/kdn/Nextcloud" = { } // snapshotsOff;
          "/home/kdn/dev" = { };
          "/nix" = { };
          "/nix/store" = { };
          "/nix/var" = { };
          "/usr" = { };
          "/var" = { } // snapshotsOn;
          "/var/lib" = { };
          "/var/lib/libvirt" = { };
          "/var/lib/microvms" = { };
          "/var/lib/nixos" = { };
          "/var/log" = { } // snapshotsOff;
          "/var/log/journal" = { };
          "/var/spool" = { };
          "/containers/storage" = { prefix = ""; mountpoint = null; } // snapshotsOff;
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
