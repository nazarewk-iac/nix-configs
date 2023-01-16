{ lib, ... }:
let
  poolName = "oams-main";
  bootDevice = "/dev/disk/by-id/usb-_Patriot_Memory_070133F17AC22052-0:0";
  luksBackupDir = "/nazarewk-iskaral/secrets/luks/oams";
  luksKeyFile = "${luksBackupDir}/luks-${poolName}-keyfile.bin";
  luksHeaderBackup = "${luksBackupDir}/luks-${poolName}-header.img";
  luksHeader = "${bootDevice}-part2";
  luksUUID = "c4b9bdbc-900f-482e-8fa6-6c6824c560e9";
  #rootDevice = "/dev/disk/by-id/ata-Samsung_Portable_SSD_T5_S49TNP0KC01288A";
  rootDevice = "/dev/disk/by-id/nvme-uuid.ae7c454b-9a04-ed11-a91a-efd50c9bff43";
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
            # TODO: OOTB those mountpoints are owned by root:root instead of kdn:users, need to fix it
            #  - cannot set ownership on a Dataset, must mount it first https://serverfault.com/a/957682
            #  - can use tmpfiles to fix permissions on mountpoints?
            #    - see: man tmpfiles.d
            #    - see: https://search.nixos.org/options?channel=22.11&show=systemd.tmpfiles.rules&from=0&size=50&sort=relevance&type=packages&query=systemd.tmpfiles.rules
            "/home/kdn/.cache" = { } // snapshotsOff;
            "/home/kdn/.config" = { };
            "/home/kdn/.local" = { };
            "/home/kdn/.local/share" = { };
            "/home/kdn/.local/share/containers" = { } // snapshotsOff;
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
          };
        in
        (lib.attrsets.mapAttrs'
          (mountpoint: cfg: {
            name = (lib.pipe mountpoint [
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
