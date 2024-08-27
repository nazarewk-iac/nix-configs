{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.disks;
  hostname = config.networking.hostName;

  zxcDGB = lib.debug.traceValSeqN 1;

  dumbMerge = builtins.foldl' lib.attrsets.recursiveUpdate { };
in
{
  config = lib.mkMerge [
    {
      kdn.hardware.disks.devices = lib.pipe cfg.luks.volumes [
        (lib.attrsets.mapAttrs' (_: luksVol: {
          name = luksVol.target.deviceKey;
          value = {
            type = "luks";
            path = lib.mkDefault luksVol.targetSpec.path;
          };
        }))
      ];
    }
    {
      /* TODO: create a systemd `.path` to integrate into impermanence when the file first appears?
          see https://github.com/nix-community/impermanence/issues/197#issuecomment-2266171206
      */
      environment.persistence = lib.pipe cfg.impermanence [
        (lib.attrsets.mapAttrs' (name: imp: {
          inherit name;
          value = {
            persistentStoragePath = imp.mountpoint;
            enable = cfg.enable;
            hideMounts = true;
            users.root.home = "/root";
          };
        }))
      ];
      home-manager.sharedModules = [
        (hm: {
          home.persistence = lib.pipe cfg.impermanence [
            (lib.attrsets.mapAttrs' (name: imp: {
              inherit name;
              value = {
                persistentStoragePath = "${imp.mountpoint}${hm.config.home.homeDirectory}";
                allowOther = true;
              };
            }))
            (lib.mkIf cfg.enable)
          ];
        })
      ];
    }
    {
      # fix all /home mountpoints permissions
      systemd.tmpfiles.rules =
        let
          users = lib.pipe config.users.users [
            (builtins.mapAttrs (n: u: u // { key = n; }))
            lib.attrsets.attrValues
            (builtins.filter (u: u.isNormalUser))
          ];
        in
        lib.trivial.pipe users [
          (builtins.map (user:
            let
              h = user.home;
              u = builtins.toString (user.uid or user.name);
              g = builtins.toString (user.gid or user.group);
              hmConfig = config.home-manager.users."${user.name}";
            in
            lib.pipe config.environment.persistence [
              (lib.filterAttrs (pName: persistence:
                let
                  hasDirectUser = persistence.users ? user.key;
                  hmPersistence = hmConfig.home.persistence."${pName}";
                  hasHMUser = hmPersistence.files != [ ] || hmPersistence.directories != [ ];
                in
                hasDirectUser || hasHMUser
              ))
              builtins.attrValues
              (builtins.map (persistence: "d ${persistence.persistentStoragePath}${h} 0750 ${u} ${g} - -"))
            ]
          ))
          lib.concatLists
        ];

      /* `root` user fixes since:
        - `systemd --user` services do not work for `root`? https://github.com/nix-community/home-manager/blob/4fcd54df7cbb1d79cbe81209909ee8514d6b17a4/modules/systemd.nix#L293-L296
      */
      environment.persistence = lib.pipe cfg.impermanence [
        (lib.attrsets.mapAttrs' (name: _: {
          inherit name;
          value = {
            users.root =
              let
                hm = config.home-manager.users.root.home.persistence."${name}";
                defaultPerms = { user = "root"; group = "root"; mode = "0700"; };
                dirConfig = defaultPerms // { inherit defaultPerms; };
              in
              {
                directories = builtins.map
                  (dir: dirConfig // { directory = if builtins.isString dir then dir else dir.directory; })
                  (hm.directories or [ ]);
                files = builtins.map
                  # hm files are always strings
                  (file: { inherit file; parentDirectory = dirConfig; })
                  (hm.files or [ ]);
              };
          };
        }))
      ];
      # clean out home manager activation since it's not needed for root
      home-manager.users.root.home.activation = lib.pipe [
        "cleanEmptyLinkTargets"
        "createAndMountPersistentStoragePaths"
        "unmountPersistentStoragePaths"
        "runUnmountPersistentStoragePaths"
        "createTargetFileDirectories"
      ] [
        (builtins.map (name: {
          inherit name;
          value = {
            after = lib.mkDefault [ ];
            before = lib.mkDefault [ ];
            data = lib.mkForce ''
              # `${name}` cleared by `kdn.hardware.disks` for `root`
            '';
          };
        }))
        builtins.listToAttrs
      ];
    }
    {
      # LUKS header partitions
      kdn.hardware.disks.devices = lib.pipe cfg.luks.volumes [
        builtins.attrValues
        (builtins.map (luksVol: {
          "${luksVol.header.deviceKey}".partitions."${luksVol.header.partitionKey}" = {
            inherit (luksVol.headerSpec) num;
            inherit (cfg.luks.header) size;
            /* https://uapi-group.org/specifications/specs/discoverable_partitions_specification/
                    Generic Linux Data Partition
                    0fc63daf-8483-4772-8e79-3d69d8477de4 SD_GPT_LINUX_GENERIC
                    Any native, optionally in LUKS
                    No automatic mounting takes place for other Linux data partitions.
                      This partition type should be used for all partitions that carry Linux file systems.
                      The installer needs to mount them explicitly via entries in /etc/fstab.
                      Optionally, these partitions may be encrypted with LUKS.
                      This partition type predates the Discoverable Partitions Specification.
                   */
            disko.type = "0FC63DAF-8483-4772-8E79-3D69D8477DE4";
            disko.label = luksVol.header.partitionKey;
          };
        }))
        dumbMerge
      ];
    }
    (lib.mkIf cfg.enable (lib.mkMerge [
      {
        # prepare LUKS volumes
        disko.devices.disk = lib.pipe cfg.luks.volumes [
          (builtins.mapAttrs (name: luksVol: {
            type = "disk";
            device = luksVol.target.path;
            content = dumbMerge [
              {
                type = "luks";
                name = luksVol.name;
                settings.header = luksVol.header.path;
                askPassword = lib.mkDefault luksVol.keyFile == null;
                extraFormatArgs = [
                  "--uuid=${luksVol.uuid}"
                  "--header=${luksVol.header.path}"
                ] ++ lib.lists.optional (luksVol.keyFile != null) "--key-file=${luksVol.keyFile}";
                extraOpenArgs = [
                  "--header=${luksVol.header.path}"
                ] ++ lib.lists.optional (luksVol.keyFile != null) "--key-file=${luksVol.keyFile}";
                content = lib.mkIf (luksVol.zpool.name != null) {
                  type = "zfs";
                  pool = luksVol.zpool.name;
                };
              }
              luksVol.disko
            ];
          }))
        ];
      }
      {
        # prepare GPT disks
        disko.devices.disk = lib.pipe cfg.devices [
          (lib.attrsets.filterAttrs (name: disk: disk.type == "gpt"))
          (builtins.mapAttrs (name: disk: dumbMerge [
            {
              type = "disk";
              device = disk.path;
              content.type = "gpt";
              content.partitions = lib.pipe disk.partitions [
                (builtins.mapAttrs (name: part: dumbMerge [
                  {
                    priority = part.num;
                    device = part.path;
                    alignment = 1 * 1024 /*MiB*/ * 1024 /*KiB*/ / 2048 /* sgdisk sector size */;
                    size = "${builtins.toString part.size}M"; # `M` equals `MiB` in sgdisk/disko, but disko validates `M`
                  }
                  part.disko
                ]))
              ];
            }
            disk.disko
          ]))
        ];
      }
      {
        disko.devices.zpool = lib.pipe cfg.zpools [
          (builtins.mapAttrs (name: zpool: dumbMerge [
            {
              type = "zpool";
              name = name;
              mode =
                let
                  volCount = lib.pipe cfg.luks.volumes [
                    builtins.attrValues
                    (builtins.filter (luksVol: luksVol.zpool.name == name))
                    builtins.length
                  ];
                in
                if volCount > 1 then "mirror" else "";
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
                autotrim = "on";
                "feature@large_dnode" = "enabled"; # required by dnodesize!=legacy
              };
            }
            zpool.disko
          ]))
        ];
      }
      {
        fileSystems = lib.pipe cfg.impermanence [
          builtins.attrValues
          (builtins.map (imp: imp.neededForBoot))
          lib.lists.flatten
          lib.unique
          (builtins.map (path: { name = path; value = { neededForBoot = true; }; }))
          builtins.listToAttrs
        ];
        disko.devices.zpool = lib.pipe cfg.impermanence [
          (builtins.mapAttrs (name: imp: {
            "${imp.zpool.name}".datasets."${imp.zfsPath}" = {
              type = "zfs_fs";
              inherit (imp) mountpoint;
              options = {
                inherit (imp) mountpoint;
                "com.sun:auto-snapshot" = builtins.toJSON imp.snapshots;
              };
            };
          }))
          builtins.attrValues
          dumbMerge
        ];
      }
      {
        # unlocking zpools in proper order
        boot.zfs.forceImportRoot = false;
        boot.zfs.extraPools = builtins.attrNames cfg.zpools;
        boot.initrd.systemd.services = lib.pipe cfg.zpools [
          (builtins.mapAttrs (name: zpool: [
            {
              name = "zfs-import-${name}";
              value = {
                requires = zpool.cryptsetup.services;
                after = zpool.cryptsetup.services;
                requiredBy = [ "initrd-fs.target" ];
                onFailure = [ zpool.initrd.failureTarget ];
                serviceConfig.TimeoutSec = zpool.import.timeout;
              };
            }
          ] ++ lib.pipe zpool.cryptsetup.names [
            (builtins.map (cryptsetupName: {
              name = cryptsetupName;
              value = {
                overrideStrategy = "asDropin";
                requires = zpool.cryptsetup.requires;
                after = zpool.cryptsetup.requires;
                # TODO: replace `systemd-udev-settle.service` with https://superuser.com/a/851966/1963591
                wants = [ "systemd-udev-settle.service" ];
                onFailure = [ zpool.initrd.failureTarget ];
                serviceConfig.TimeoutSec = zpool.import.timeout;
              };
            }))
          ]))
          builtins.attrValues
          lib.lists.flatten
          builtins.listToAttrs
        ];
      }
    ]))
  ];
}
