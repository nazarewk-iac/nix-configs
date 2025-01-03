{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hardware.disks;
  hostname = config.networking.hostName;

  zxcDGB = lib.debug.traceValSeqN 1;

  dumbMerge = builtins.foldl' lib.attrsets.recursiveUpdate {};
in {
  # look for conditionally enabled modules below
  config = lib.mkMerge [
    (lib.mkIf cfg.enable (lib.mkMerge [
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
        /*
        TODO: create a systemd `.path` to integrate into impermanence when the file first appears?
         see https://github.com/nix-community/impermanence/issues/197#issuecomment-2266171206
        */
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
            ];
          })
        ];
      }
      {
        # fix all /home mountpoints permissions
        systemd.tmpfiles.rules = let
          users = lib.pipe config.users.users [
            (builtins.mapAttrs (n: u: u // {key = n;}))
            lib.attrsets.attrValues
            (builtins.filter (u: u.isNormalUser))
          ];
        in
          lib.trivial.pipe users [
            (builtins.map (
              user: let
                h = user.home;
                u = builtins.toString (user.uid or user.name);
                g = builtins.toString (user.gid or user.group);
                hmConfig = config.home-manager.users."${user.name}";
                mode = config.impermanence.userDefaultPerms.mode;
              in
                lib.pipe config.environment.persistence [
                  builtins.attrValues
                  (builtins.map (persistence: "d ${persistence.persistentStoragePath}${h} ${mode} ${u} ${g} - -"))
                ]
            ))
            builtins.concatLists
            (lib.mkOrder 499)
          ];
      }
      {
        /*
        `root` user hardcodes
        */
        environment.persistence = lib.pipe cfg.impermanence [
          (builtins.mapAttrs (name: imp: {
            persistentStoragePath = imp.mountpoint;
            enable = cfg.enable;
            hideMounts = true;
            users.root.home = "/root";
          }))
        ];
        home-manager.users.root.impermanence = {
          /*
          `systemd --user` services do not work for `root`? https://github.com/nix-community/home-manager/blob/4fcd54df7cbb1d79cbe81209909ee8514d6b17a4/modules/systemd.nix#L293-L296
           so we want to handle those mounts ourselves on NixOS side
          */
          defaultDirectoryMethod = "external";
          defaultFileMethod = "external";
        };
      }
      {
        environment.persistence = lib.pipe cfg.impermanence [
          (builtins.mapAttrs (name: imp:
            lib.pipe config.home-manager.users [
              (lib.attrsets.mapAttrsToList (username: hmConfig: {
                users.${username} = let
                  hm = hmConfig.home.persistence."${name}";
                  defaultPerms = {
                    user = username;
                    group =
                      if username == "root"
                      then "root"
                      else "users";
                    mode = lib.mkForce config.impermanence.userDefaultPerms.mode;
                  };
                  dirConfig = defaultPerms // {inherit defaultPerms;};
                in {
                  directories = lib.pipe (hm.directories or []) [
                    (builtins.filter (e: e.method == "external"))
                    (builtins.map (dir:
                      dirConfig
                      // {
                        directory =
                          if builtins.isString dir
                          then dir
                          else dir.directory;
                      }))
                  ];
                  files = lib.pipe (hm.files or []) [
                    (builtins.filter (e: e.method == "external"))
                    (builtins.map (file: {
                      file = file.file;
                      parentDirectory = dirConfig;
                    }))
                  ];
                };
              }))
              lib.mkMerge
            ]))
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
              /*
              https://uapi-group.org/specifications/specs/discoverable_partitions_specification/
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
                extraFormatArgs =
                  [
                    "--uuid=${luksVol.uuid}"
                    "--header=${luksVol.header.path}"
                  ]
                  ++ lib.lists.optional (luksVol.keyFile != null) "--key-file=${luksVol.keyFile}";
                extraOpenArgs =
                  [
                    "--header=${luksVol.header.path}"
                  ]
                  ++ lib.lists.optional (luksVol.keyFile != null) "--key-file=${luksVol.keyFile}";
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
          (builtins.mapAttrs (name: disk:
            dumbMerge [
              {
                type = "disk";
                device = disk.path;
                content.type = "gpt";
                content.partitions = lib.pipe disk.partitions [
                  (builtins.mapAttrs (name: part:
                    dumbMerge [
                      {
                        priority = part.num;
                        device = part.path;
                        alignment =
                          1
                          * 1024
                          /*
                          MiB
                          */
                          * 1024
                          /*
                          KiB
                          */
                          / 2048
                          /*
                          sgdisk sector size
                          */
                          ;
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
          (builtins.mapAttrs (name: zpool:
            dumbMerge [
              {
                type = "zpool";
                name = name;
                mode = let
                  volCount = lib.pipe cfg.luks.volumes [
                    builtins.attrValues
                    (builtins.filter (luksVol: luksVol.zpool.name == name))
                    builtins.length
                  ];
                in
                  if volCount > 1
                  then "mirror"
                  else "";
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
          (builtins.map (path: {
            name = path;
            value = {neededForBoot = true;};
          }))
          builtins.listToAttrs
        ];
        disko.devices.zpool = lib.pipe cfg.impermanence [
          (builtins.mapAttrs (name: imp: {
            "${imp.zpool.name}".datasets."${imp.zfsPath}" = dumbMerge [
              {
                type = "zfs_fs";
                inherit (imp) mountpoint;
                options = {
                  inherit (imp) mountpoint;
                  "com.sun:auto-snapshot" = builtins.toJSON imp.snapshots;
                };
              }
              imp.disko
            ];
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
          (builtins.mapAttrs (name: zpool:
            [
              {
                name = "zfs-import-${name}";
                value = {
                  requires = zpool.cryptsetup.services;
                  after = zpool.cryptsetup.services;
                  requiredBy = ["initrd-fs.target"];
                  onFailure = [zpool.initrd.failureTarget];
                  serviceConfig.TimeoutSec = zpool.import.timeout;
                };
              }
            ]
            ++ lib.pipe zpool.cryptsetup.names [
              (builtins.map (cryptsetupName: {
                name = cryptsetupName;
                value = {
                  overrideStrategy = "asDropin";
                  requires = zpool.cryptsetup.requires;
                  after = zpool.cryptsetup.requires;
                  # TODO: replace `systemd-udev-settle.service` with https://superuser.com/a/851966/1963591
                  wants = ["systemd-udev-settle.service"];
                  onFailure = [zpool.initrd.failureTarget];
                  serviceConfig.TimeoutSec = zpool.import.timeout;
                };
              }))
            ]))
          builtins.attrValues
          lib.lists.flatten
          builtins.listToAttrs
        ];
      }
      {
        environment.persistence = lib.pipe cfg.users [
          (lib.attrsets.mapAttrsToList (username: userCfg: {
            "${userCfg.homeLocation}".users."${username}".directories = [""];
          }))
          lib.mkMerge
        ];
      }
      (let
        dImp = cfg.impermanence."disposable";
        snapshotName = "${dImp.zpool.name}/${dImp.zfsPath}@empty";
        scriptDeps = [config.boot.zfs.package];
      in {
        /*
        Migrating on a live system:
          zfs rename -u brys-main/brys/impermanence/disposable{,.old}
          zfs set -u mountpoint=/nix/persist/disposable.old brys-main/brys/impermanence/disposable.old
          zfs create -u brys-main/brys/impermanence/disposable -o mountpoint=/nix/persist/disposable
          # nixos-rebuild boot
          # reboot
          zfs destroy brys-main/brys/impermanence/disposable.old
        */
        kdn.hardware.disks.impermanence."disposable".zfsName = cfg.disposable.zfsName;
        kdn.hardware.disks.impermanence."disposable".disko.postCreateHook = ''
          zfs snapshot "${snapshotName}"
        '';
        environment.persistence."disposable".directories = [
          {
            directory = "/var/tmp";
            mode = "0777";
          }
        ];
        boot.initrd.systemd.initrdBin = scriptDeps;
        boot.initrd.systemd.services."kdn-disks-disposable-rollback" = {
          description = ''rollbacks `disposable` filesystem to empty state'';
          after = ["zfs-import-${dImp.zpool.name}.service"];
          wantedBy = [
            "sysroot-nix-persist-disposable.mount"
            "zfs-import-${dImp.zpool.name}.service"
          ];
          before = ["sysroot-nix-persist-disposable.mount"];
          onFailure = ["rescue.target"];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          unitConfig.DefaultDependencies = false;
          script = ''zfs rollback -r "${snapshotName}"'';
        };
      })
    ]))
  ];
}
