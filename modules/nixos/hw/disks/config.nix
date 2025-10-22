{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hw.disks;

  # TODO: make the ZFS pools/datasets optional and fall back to /nix/persist/fallback?

  dumbMerge = builtins.foldl' lib.attrsets.recursiveUpdate {};
in {
  config = lib.mkMerge [
    {home-manager.sharedModules = [{kdn.hw.disks.enable = cfg.enable;}];}
    {
      preservation.enable = lib.mkDefault cfg.enable;
      kdn.hw.disks.persist = lib.pipe cfg.base [
        (builtins.mapAttrs (_: _: {}))
      ];
      preservation.preserveAt = lib.pipe cfg.base [
        (builtins.mapAttrs (
          persistName: baseCfg: let
            persists = cfg.persist."${persistName}";
          in {
            commonMountOptions = [
              "x-gvfs-hide" # hide the mounts by default
              "x-gdu.hide" # hide the mounts by default
            ];
            persistentStoragePath = baseCfg.mountpoint;
            inherit (persists) directories files;
            users =
              builtins.mapAttrs (
                username: hmConfig: let
                  homeDirMode = (cfg.users."${username}" or cfg.userDefaults).homeDirMode;
                  homeFileMode = (cfg.users."${username}" or cfg.userDefaults).homeFileMode;
                  process = topName: childName: mode:
                    lib.pipe
                    [
                      (hmConfig.kdn.hw.disks.persist."${persistName}" or {})
                      (persists.users."${username}" or {})
                    ]
                    [
                      (builtins.catAttrs topName)
                      builtins.concatLists
                      (builtins.map (
                        c: let
                          d =
                            if builtins.typeOf c == "string"
                            then {"${childName}" = c;}
                            else c;
                        in
                          {
                            inherit mode;
                          }
                          // d
                          // {
                            parent =
                              {
                                mode = homeDirMode;
                              }
                              // (d.parent or {});
                          }
                      ))
                    ];
                in {
                  files = process "files" "file" homeFileMode;
                  directories = process "directories" "directory" homeDirMode;
                }
              )
              config.home-manager.users;
          }
        ))
        (lib.mkIf cfg.enable)
      ];
    }
    {
      kdn.hw.disks.devices = lib.pipe cfg.luks.volumes [
        (lib.attrsets.mapAttrs' (
          _: luksVol: {
            name = luksVol.target.deviceKey;
            value = {
              type = "luks";
              path = lib.mkDefault luksVol.targetSpec.path;
            };
          }
        ))
      ];
    }
    {
      # LUKS header partitions
      kdn.hw.disks.devices = lib.pipe cfg.luks.volumes [
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
      kdn.hw.disks.users = builtins.mapAttrs (_: _: {}) config.home-manager.users;
      systemd.services = lib.pipe config.home-manager.users [
        # see https://github.com/nix-community/home-manager/blob/1c8d4c8d592e8fab4cff4397db5529ec6f078cf9/nixos/default.nix#L39-L39
        (lib.attrsets.mapAttrs' (
          _: hmConfig: {
            name = "home-manager-${hmConfig.home.username}";
            value.after = ["preservation.target"];
            value.requires = ["preservation.target"];
          }
        ))
        (lib.mkIf cfg.enable)
      ];
    }
    (
      let
        baseCfg = cfg.base."disposable";
        snapshotName = "${baseCfg.zpool.name}/${baseCfg.zfsPath}@empty";
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
        kdn.hw.disks.base."disposable".snapshots = false;
        kdn.hw.disks.base."disposable".zfsName = cfg.disposable.zfsName;
        # this does not always work
        kdn.hw.disks.base."disposable".disko.postCreateHook = ''
          zfs snapshot "${snapshotName}"
        '';
        kdn.hw.disks.persist."disposable".directories = [
          {
            directory = "/var/tmp";
            mode = "0777";
          }
        ];
        boot.initrd.systemd.initrdBin = lib.mkIf cfg.enable scriptDeps;
        boot.initrd.systemd.services = lib.mkIf cfg.enable {
          "kdn-disks-disposable-rollback" = {
            description = ''rollbacks `disposable` filesystem to empty state'';
            after = ["zfs-import-${baseCfg.zpool.name}.service"];
            requiredBy = ["zfs-import-${baseCfg.zpool.name}.service"];
            wantedBy = ["sysroot-nix-persist-disposable.mount"];
            before = ["sysroot-nix-persist-disposable.mount"];
            onFailure = ["rescue.target"];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              RestartSec = "3";
              Restart = "on-failure";
            };
            unitConfig.DefaultDependencies = false;
            unitConfig.StartLimitInterval = 60;
            unitConfig.StartLimitBurst = 3;
            script = ''
              if ! zfs rollback -r "${snapshotName}"; then
                test -d /sysroot/nix/persist/disposable
                rm -rf /sysroot/nix/persist/disposable/*
                zfs snapshot "${snapshotName}"
              fi
            '';
          };
        };
      }
    )
    {systemd.tmpfiles.settings.preservation = {};}
    {
      # $HOME directories creation
      preservation.preserveAt = lib.pipe cfg.users [
        (lib.attrsets.mapAttrsToList (
          username: userCfg: let
            sysUser = config.users.users."${username}";
          in {
            "${userCfg.homeLocation}".directories = [
              {
                directory = sysUser.home;
                user = sysUser.name;
                group = sysUser.group;
                mode = userCfg.homeDirMode;
              }
            ];
          }
        ))
        lib.mkMerge
        (lib.mkIf cfg.enable)
      ];

      # fixup all in-between home subdirectory permissions
      # feature request: https://github.com/nix-community/preservation/issues/9
      systemd.tmpfiles.settings.zzz-kdn-preservation-users = lib.mkIf cfg.enable (
        lib.pipe config.preservation.preserveAt [
          (lib.attrsets.mapAttrsToList (
            _: preserveAtCfg:
              lib.pipe preserveAtCfg.users [
                (lib.attrsets.mapAttrsToList (
                  _: preserveAtUserCfg: let
                    inherit (preserveAtUserCfg) username;
                    persistUserCfg = cfg.users."${username}";
                    splitHome = lib.strings.splitString "/" preserveAtUserCfg.home;
                    splitHomeLen = builtins.length splitHome;

                    parentDirs =
                      lib.pipe preserveAtUserCfg.files [
                        (builtins.map (f: builtins.dirOf f.file))
                      ]
                      ++ lib.pipe preserveAtUserCfg.directories [
                        (builtins.map (f: builtins.dirOf f.directory))
                      ];

                    missingDirs = lib.pipe parentDirs [
                      (builtins.map (
                        dir:
                          lib.pipe dir [
                            (lib.strings.splitString "/")
                            (
                              pieces:
                                builtins.genList (
                                  i:
                                    lib.pipe pieces [
                                      (lib.lists.sublist 0 (splitHomeLen + i + 1))
                                      (builtins.concatStringsSep "/")
                                    ]
                                ) (builtins.length pieces - splitHomeLen)
                            )
                          ]
                      ))
                      lib.lists.flatten
                      (builtins.map (
                        dir: let
                          conf = {
                            mode = persistUserCfg.homeDirMode;
                            user = username;
                            group = config.users.users."${username}".group;
                          };
                        in {
                          "${preserveAtCfg.persistentStoragePath}${dir}".d = conf;
                          "${dir}".d = conf;
                        }
                      ))
                    ];
                  in
                    missingDirs
                ))
              ]
          ))
          lib.lists.flatten
          lib.lists.unique
          lib.mkMerge
        ]
      );
    }
    {
      # fix up missing mkdirs on non-user parents
      systemd.tmpfiles.settings.zzz-kdn-preservation-system = lib.mkIf cfg.enable (
        lib.pipe config.preservation.preserveAt [
          (lib.attrsets.mapAttrsToList (
            _: preserveAtCfg: let
              parentDirs =
                lib.pipe preserveAtCfg.files [
                  (builtins.map (f: {
                    path = builtins.dirOf f.file;
                    conf = f.parent;
                  }))
                ]
                ++ lib.pipe preserveAtCfg.directories [
                  (builtins.map (f: {
                    path = builtins.dirOf f.directory;
                    conf = f.parent;
                  }))
                ];

              # TODO: get rid of duplicates compared to `config.systemd.tmpfiles.settings.preservation`?
              missingDirs = lib.pipe parentDirs [
                (builtins.filter (entry: entry.path != "" && entry.path != "/"))
                (builtins.map (
                  entry:
                    lib.flip builtins.map
                    [
                      "${preserveAtCfg.persistentStoragePath}${entry.path}"
                      "${entry.path}"
                    ]
                    (key: {
                      "${key}".d = entry.conf;
                    })
                ))
              ];
            in
              missingDirs
          ))
          lib.lists.flatten
          lib.lists.unique
          lib.mkMerge
        ]
      );
    }
    {
      # prepare LUKS volumes
      disko.devices.disk = lib.pipe cfg.luks.volumes [
        (builtins.mapAttrs (
          name: luksVol: {
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
          }
        ))
        (lib.mkIf cfg.enable)
      ];
    }
    {
      # prepare GPT disks
      disko.devices.disk = lib.pipe cfg.devices [
        (lib.attrsets.filterAttrs (name: disk: disk.type == "gpt"))
        (builtins.mapAttrs (
          name: disk:
            dumbMerge [
              {
                type = "disk";
                device = disk.path;
                content.type = "gpt";
                content.partitions = lib.pipe disk.partitions [
                  (builtins.mapAttrs (
                    name: part:
                      dumbMerge [
                        {
                          priority = part.num;
                          device = part.path;
                          alignment =
                            1
                            * 1024
                            # MiB
                            * 1024
                            # KiB
                            / 2048
                            # sgdisk sector size
                            ;
                          size = "${builtins.toString part.size}M"; # `M` equals `MiB` in sgdisk/disko, but disko validates `M`
                        }
                        part.disko
                      ]
                  ))
                ];
              }
              disk.disko
            ]
        ))
        (lib.mkIf cfg.enable)
      ];
    }
    {
      disko.devices.zpool = lib.pipe cfg.zpools [
        (builtins.mapAttrs (
          name: zpool:
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
            ]
        ))
        (lib.mkIf cfg.enable)
      ];
    }
    {
      fileSystems = lib.pipe cfg.base [
        builtins.attrValues
        (builtins.map (imp: imp.neededForBoot))
        lib.lists.flatten
        lib.unique
        (builtins.map (path: {
          name = path;
          value = {
            neededForBoot = true;
          };
        }))
        builtins.listToAttrs
        (lib.mkIf cfg.enable)
      ];
      disko.devices.zpool = lib.pipe cfg.base [
        (builtins.mapAttrs (
          name: imp: {
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
          }
        ))
        builtins.attrValues
        dumbMerge
        (lib.mkIf cfg.enable)
      ];
    }
    {
      # unlocking zpools in proper order
      boot.zfs.forceImportRoot = false;
      boot.zfs.extraPools = builtins.attrNames cfg.zpools;
      boot.initrd.systemd.services = lib.pipe cfg.zpools [
        (builtins.mapAttrs (
          name: zpool:
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
            ]
        ))
        builtins.attrValues
        lib.lists.flatten
        builtins.listToAttrs
        (lib.mkIf cfg.enable)
      ];
    }
    (lib.mkIf cfg.enable {
      # enables systemd-cryptsetup-generator
      # see https://github.com/nazarewk/nixpkgs/blob/04f574a1c0fde90b51bf68198e2297ca4e7cccf4/nixos/modules/system/boot/luksroot.nix#L997-L1012
      boot.initrd.luks.forceLuksSupportInInitrd = true;
      boot.initrd.systemd.enable = true;

      disko.enableConfig = true;
      kdn.fs.zfs.enable = true;
      kdn.security.disk-encryption.enable = true;
      boot.zfs.requestEncryptionCredentials = false;
    })
  ];
}
