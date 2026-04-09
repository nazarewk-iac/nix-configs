{
  lib,
  hostname ? "obler",
  luksUUID ? "c7f78f0a-9da2-408a-bd89-9688b8440add",
  rootDevice ? "/dev/disk/by-id/ata-SK_hynix_SC311_SATA_256GB_MS83N489310403C1D",
  ...
}:
let
  poolName = "${hostname}-main";
  luksKeyFile = "/run/media/kdn/df4ba496-1af2-45d7-ae05-0186c608aeb6/obler/luks-keyfile.bin";
in
{
  disko.devices = {
    disk.root = {
      type = "disk";
      device = rootDevice;
      content.type = "gpt";
      content.partitions.ESP = {
        device = "${rootDevice}-part1";
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
      content.partitions.luks = {
        device = "${rootDevice}-part2";
        size = "100%";
        content = {
          type = "luks";
          name = "${poolName}-crypted";
          settings.crypttabExtraOpts = [ "fido2-device=auto" ];
          additionalKeyFiles = [ luksKeyFile ];
          extraFormatArgs = [
            "--uuid=${luksUUID}"
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
          snapshotsOn = {
            options."com.sun:auto-snapshot" = "true";
          };
          snapshotsOff = {
            options."com.sun:auto-snapshot" = "false";
          };
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
          (lib.attrsets.mapAttrs' (
            mp: cfg:
            let
              mountpoint = cfg.options.mountpoint or cfg.mountpoint or mp;
            in
            {
              name = lib.trivial.pipe mp [
                (p: "${cfg.prefix or filesystemPrefix}${p}")
                (lib.strings.removeSuffix "/")
              ];
              value = {
                type = "zfs_fs";
                mountpoint = if mountpoint != "none" then mountpoint else null;

                # note: disko handles non-legacy mountpoints with `-o zfsutil` mount option
                options = {
                  mountpoint = if mountpoint != null then mountpoint else "none";
                }
                // cfg.options or { };
              }
              // (builtins.removeAttrs cfg [
                "prefix"
                "options"
              ]);
            }
          ))
        ];
    };
  };
}
