{ lib, ... }:
let
  poolName = "obler-main";
  bootDevice = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04LZCR91M8UZPJW8-0:0";
  luksBackupDir = "";
  luksKeyFile = "${luksBackupDir}/luks-${poolName}-keyfile.bin";
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
            type = "partition";
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
            type = "partition";
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
        extraArgsFormat = [
          "--uuid=${luksUUID}"
          "--header=${luksHeader}"
          "--header-backup-file=${luksHeaderBackup}"
        ];
        extraArgsOpen = [
          "--header=${luksHeader}"
        ];
        content = {
          type = "zfs";
          pool = poolName;
        };
      };
    };
  };

  zpool = {
    "${poolName}" = {
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
        (lib.attrsets.mapAttrs'
          (mountpoint: cfg: {
            name = (lib.trivial.pipe mountpoint [
              (p: "${filesystemPrefix}${p}")
              (lib.strings.removeSuffix "/")
            ]);
            value = ({
              zfs_type = "filesystem";
              inherit mountpoint;

              # disko handles non-legacy mountpoints with `-o zfsutil` mount option
              options = { inherit mountpoint; };
              #options.mountpoint =
              #  # required legacy mountpoints due to using `mount -t zfs` instead of `zfs mount` or `zpool import -R`
              #  # see https://github.com/NixOS/nixpkgs/blob/c07552f6f7d4eead7806645ec03f7f1eb71ba6bd/nixos/lib/utils.nix#L13-L13
              #  # ["/" "/nix" "/nix/store" "/var" "/var/log" "/var/lib" "/var/lib/nixos" "/etc" "/usr"];
              #  if builtins.elem mountpoint [ "/" "/nix" "/nix/store" "/var" "/var/log" "/var/lib" "/var/lib/nixos" "/etc" "/usr" ]
              #  then "legacy"
              #  else mountpoint;
            } // cfg);
          })
          mounts);
    };
  };
}
