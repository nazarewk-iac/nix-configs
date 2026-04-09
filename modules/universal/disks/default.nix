# TODO: add check not to be enabled on darwin?
{
  lib,
  pkgs,
  config,
  options,
  utils ? null,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.disks;
  hostname = config.kdn.hostName;

  partSizeType =
    with lib.types;
    oneOf [
      str
      ints.positive
    ];

  deviceType = lib.types.submodule (
    { name, ... }@disk:
    {
      options.type = lib.mkOption {
        type = lib.types.enum [
          "gpt"
          "luks"
        ];
        default = "gpt";
      };
      options.path = lib.mkOption {
        type = lib.types.path;
      };
      options.disko = lib.mkOption {
        default = { };
      };
      options.partitions = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }@part:
            {
              options.num = lib.mkOption {
                type = lib.types.ints.between 1 128;
              };
              options.path = lib.mkOption {
                internal = true;
                type = lib.types.path;
                default =
                  let
                    _path = disk.config.path;
                    partNum = toString part.config.num;
                  in
                  if lib.strings.hasPrefix "/dev/disk/" _path then
                    "${_path}-part${partNum}"
                  else if (builtins.match "/dev/[^/]+" _path) != null then
                    "${_path}${partNum}"
                  else
                    throw "Don't know how to generate partition number for disk ${_path}";
              };
              options.size = lib.mkOption {
                type = partSizeType;
              };
              options.disko = lib.mkOption {
                default = { };
              };
            }
          )
        );
      };
    }
  );

  deviceSelectorType = lib.types.submodule (
    {
      name,
      config,
      ...
    }@partSel:
    {
      options.deviceKey = lib.mkOption {
        type = with lib.types; nullOr str;
      };
      options.partitionKey = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
      };
      options.device = lib.mkOption {
        type = deviceType;
        internal = true;
        default =
          let
            key = partSel.config.deviceKey;
          in
          cfg.devices."${key}";
      };
      options.partition = lib.mkOption {
        type = with lib.types; anything;
        default =
          with partSel.config;
          if partitionKey == null then { } else device.partitions."${partitionKey}";
      };
      options.path = lib.mkOption {
        internal = true;
        type = lib.types.path;
        default =
          if partSel.config.partition == { } then
            partSel.config.device.path
          else
            partSel.config.partition.path;
      };
    }
  );
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "kdn" "hw" "disks" ] [ "kdn" "disks" ])
  ]
  ++ lib.optional (kdnConfig.moduleType == "nixos") ./config.nix;
  options.kdn.disks = {
    enable = lib.mkOption {
      description = "enable persistence@ZFS@LUKS-volumes with detached headers and separate /boot";
      type = lib.types.bool;
      default = false;
      apply =
        value:
        assert lib.assertMsg (!(value && config.kdn.fs.disko.luks-zfs.enable)) ''
          You must choose only one of: `kdn.disks.enable` or `kdn.fs.disko.luks-zfs.enable`, not both!
        '';
        value;
    };

    nixBuildDir.type = lib.mkOption {
      type = lib.types.enum [
        "disposable"
        "tmpfs"
        "zfs-dataset"
      ];
      default = "disposable";
    };
    nixBuildDir.tmpfs.size = lib.mkOption {
      type = lib.types.str;
      default = "2G";
    };

    users = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }@userArgs:
          {
            options.homeLocation = lib.mkOption {
              type = lib.types.enum (builtins.attrNames cfg.base);
              default = cfg.userDefaults.homeLocation;
            };
            options.homeDirMode = lib.mkOption {
              type = with lib.types; str;
              default = cfg.userDefaults.homeDirMode;
            };
            options.homeFileMode = lib.mkOption {
              type = with lib.types; str;
              default = cfg.userDefaults.homeFileMode;
            };
          }
        )
      );
    };

    userDefaults.homeLocation = lib.mkOption {
      type = lib.types.enum (builtins.attrNames cfg.base);
      description = "which disks config should $HOME come from?";
    };
    userDefaults.homeFileMode = lib.mkOption {
      type = with lib.types; str;
      default = "0640";
    };
    userDefaults.homeDirMode = lib.mkOption {
      type = with lib.types; str;
      default = "0750";
    };

    defaults.mountPrefix = lib.mkOption {
      type = with lib.types; path;
      default = "/nix/persist";
    };
    defaults.bootDeviceName = lib.mkOption {
      type = with lib.types; str;
      default = "boot";
    };

    disposable.zfsName = lib.mkOption {
      type = with lib.types; str;
      default = "disposable";
    };

    luks.header.size = lib.mkOption {
      type = partSizeType;
      # https://wiki.archlinux.org/title/Dm-crypt/Device_encryption#Encrypt_an_existing_unencrypted_file_system
      # suggests using 32MB == 2x header size (16MB)
      default = 32;
    };

    tmpfs.size = lib.mkOption {
      type = lib.types.str;
      default = "16M";
    };

    zpool-main.name = lib.mkOption {
      type = lib.types.str;
      default = "${config.kdn.hostName}-main";
    };
    initrd.failureTarget = lib.mkOption {
      type = lib.types.str;
      default = "emergency.target";
    };

    devices = lib.mkOption {
      type = lib.types.attrsOf deviceType;
      default = { };
    };
    luks.volumes = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }@luksVol:
          {
            options.target = lib.mkOption {
              type = deviceSelectorType;
            };
            options.targetSpec.path = lib.mkOption {
              type = with lib.types; nullOr path;
              default = luksVol.config.target.partition.path;
            };
            options.targetSpec.partNum = lib.mkOption {
              type = lib.types.ints.between 1 128;
            };
            options.targetSpec.size = lib.mkOption {
              type = partSizeType;
            };
            options.uuid = lib.mkOption {
              type = lib.types.str;
            };
            options.keyFile = lib.mkOption {
              type = with lib.types; nullOr str;
              /*
                configuring disko's `settings.keyFile` puts the keyFile in the systemd service
                 preventing it from working with TPM2/YubiKey etc.
              */
              default = "/tmp/${luksVol.name}.key";
            };
            options.header = lib.mkOption {
              type = deviceSelectorType;
            };
            options.headerSpec.partNum = lib.mkOption {
              type = lib.types.ints.between 1 128;
            };
            options.name = lib.mkOption {
              type = lib.types.str;
              default = "${luksVol.name}-crypted";
            };
            options.disko = lib.mkOption {
              default = { };
            };
            options.zpool.name = lib.mkOption {
              type = with lib.types; nullOr str;
              default = cfg.zpool-main.name;
            };
            config = {
              target.deviceKey = lib.mkDefault luksVol.name;
              target.partitionKey = lib.mkDefault null;
              header.deviceKey = lib.mkDefault cfg.defaults.bootDeviceName;
              header.partitionKey = lib.mkDefault "${luksVol.name}-header";
            };
          }
        )
      );
    };
    zpools = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }@zpool:
          {
            options.disko = lib.mkOption {
              default = { };
            };
            options.import.timeout = lib.mkOption {
              type = with lib.types; int;
              default = 15;
            };
            options.cryptsetup.requires = lib.mkOption {
              type = with lib.types; listOf str;
              default = [ ];
            };
            options.cryptsetup.names = lib.mkOption {
              type = with lib.types; listOf str;
              default = lib.trivial.pipe cfg.luks.volumes [
                (lib.filterAttrs (luksVolName: luksVol: luksVol.zpool.name == zpool.name))
                (builtins.mapAttrs (luksVolName: luksVol: luksVol.name))
                builtins.attrValues
                (map (luksName: "systemd-cryptsetup@${utils.escapeSystemdPath luksName}"))
              ];
            };
            options.cryptsetup.services = lib.mkOption {
              type = with lib.types; listOf str;
              default = map (name: "${name}.service") zpool.config.cryptsetup.names;
            };
            options.initrd.failureTarget = lib.mkOption {
              type = with lib.types; str;
              default = cfg.initrd.failureTarget;
            };
          }
        )
      );
    };
    persist = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.directories = lib.mkOption {
            type = lib.types.listOf (
              lib.types.either lib.types.str (
                lib.types.submodule { freeformType = (pkgs.formats.json { }).type; }
              )
            );
            default = [ ];
          };
          options.files = lib.mkOption {
            type = lib.types.listOf (
              lib.types.either lib.types.str (
                lib.types.submodule { freeformType = (pkgs.formats.json { }).type; }
              )
            );
            default = [ ];
          };
          options.users = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                freeformType = (pkgs.formats.json { }).type;
                options.directories = lib.mkOption {
                  type = lib.types.listOf (
                    lib.types.either lib.types.str (
                      lib.types.submodule { freeformType = (pkgs.formats.json { }).type; }
                    )
                  );
                  default = [ ];
                };
                options.files = lib.mkOption {
                  type = lib.types.listOf (
                    lib.types.either lib.types.str (
                      lib.types.submodule { freeformType = (pkgs.formats.json { }).type; }
                    )
                  );
                  default = [ ];
                };
              }
            );
            default = { };
          };
        }
      );
    };
    base = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }@baseArgs:
          let
            baseCfg = baseArgs.config;
          in
          {
            options.neededForBoot = lib.mkOption {
              type = with lib.types; listOf path;
              default = [ ];
              apply = ls: [ "${baseCfg.mountpoint}" ] ++ ls;
            };
            options.mountpoint = lib.mkOption {
              type = with lib.types; str;
              default = "${baseCfg.mountPrefix}/${baseArgs.name}";
            };
            options.mountPrefix = lib.mkOption {
              type = with lib.types; str;
              default = cfg.defaults.mountPrefix;
            };
            options.zfsName = lib.mkOption {
              type = with lib.types; str;
              default = baseArgs.name;
            };
            options.zfsPrefix = lib.mkOption {
              type = with lib.types; str;
              default = "${config.kdn.hostName}/impermanence";
            };
            options.zfsPath = lib.mkOption {
              type = with lib.types; str;
              default = "${baseCfg.zfsPrefix}/${baseCfg.zfsName}";
            };
            options.zpool.name = lib.mkOption {
              type = with lib.types; nullOr str;
              default = cfg.zpool-main.name;
            };
            options.snapshots = lib.mkOption {
              type = with lib.types; bool;
            };
            options.disko = lib.mkOption {
              # this type doesn't work
              #type = lib.types.attrsOf (lib.types.submodule {freeformType = (pkgs.formats.json {}).type;});
              default = { };
            };
          }
        )
      );
    };
    disko.devices._meta = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
    };
    disko.debug = lib.mkOption {
      readOnly = true;
      default =
        let
          diskoLib = pkgs.lib.disko;
          cfg.config = config.disko.devices;
          # https://github.com/nix-community/disko/blob/5a88a6eceb8fd732b983e72b732f6f4b8269bef3/lib/default.nix#L644-L653
          devices = {
            inherit (cfg.config)
              bcachefs_filesystems
              disk
              mdadm
              zpool
              lvm_vg
              nodev
              ;
          };
          # https://github.com/nix-community/disko/blob/5a88a6eceb8fd732b983e72b732f6f4b8269bef3/lib/default.nix#L992-L993
          sortedDeviceList = diskoLib.sortDevicesByDependencies (cfg.config._meta.deviceDependencies or { }
          ) devices;
        in
        if config ? disko then
          {
            inherit (cfg.config._meta)
              deviceDependencies
              ;
            inherit
              cfg
              diskoLib
              devices
              sortedDeviceList
              ;
          }
        else
          { };
    };
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkMerge [
        (lib.mkIf cfg.enable (
          lib.mkMerge [
            {
              kdn.disks.base."sys/cache".snapshots = false;
              kdn.disks.base."sys/config".snapshots = true;
              kdn.disks.base."sys/data".snapshots = true;
              kdn.disks.base."sys/reproducible".snapshots = false;
              kdn.disks.base."sys/state".snapshots = false;
              kdn.disks.base."usr/cache".snapshots = false;
              kdn.disks.base."usr/config".snapshots = true;
              kdn.disks.base."usr/data".snapshots = true;
              kdn.disks.base."usr/reproducible".snapshots = false;
              kdn.disks.base."usr/state".snapshots = false;
              kdn.disks.userDefaults.homeLocation = lib.mkDefault "disposable";
            }
            {
              # Basic /boot config
              fileSystems."/boot".neededForBoot = true;
              kdn.disks.devices."${cfg.defaults.bootDeviceName}" = {
                type = "gpt";
                partitions."ESP" = {
                  num = 1;
                  size = 4096;
                  disko = {
                    type = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
                    label = "ESP";
                    content.type = "filesystem";
                    content.format = "vfat";
                    content.mountpoint = "/boot";
                    content.mountOptions = [
                      "fmask=0077"
                      "dmask=0077"
                    ];
                  };
                };
              };
            }
            {
              kdn.disks.zpools."${cfg.zpool-main.name}" = { };
            }
            {
              disko.devices.zpool."${cfg.zpool-main.name}".datasets = {
                "${hostname}/nix-system/nix-store" = {
                  type = "zfs_fs";
                  mountpoint = "/nix/store";
                  options.mountpoint = "/nix/store";
                  options.atime = "off";
                };
                "${hostname}/nix-system/nix-var" = {
                  type = "zfs_fs";
                  mountpoint = "/nix/var";
                  options.mountpoint = "/nix/var";
                };
              };
            }
            {
              kdn.disks.persist."sys/data" = {
                directories = [
                  "/var/lib/systemd"
                  {
                    directory = "/var/lib/private";
                    mode = "0700";
                  }
                ];
                files = [
                  {
                    file = "/etc/ssh/ssh_host_ed25519_key";
                    how = "symlink";
                    mode = "0600";
                    inInitrd = true;
                  }
                  {
                    file = "/etc/ssh/ssh_host_rsa_key";
                    how = "symlink";
                    mode = "0600";
                    inInitrd = true;
                  }
                ];
              };
              kdn.disks.persist."sys/config" = {
                directories = [
                  "/var/db/sudo/lectured"
                  "/var/lib/nixos"
                  "/var/lib/systemd/pstore"
                  "/var/spool"
                ];
                files = [
                  "/etc/printcap"
                ];
              };
            }
            {
              kdn.disks.persist."sys/config".files = [
                {
                  file = "/etc/machine-id";
                  inInitrd = true;
                  configureParent = true;
                }
              ];
              systemd.services.systemd-machine-id-commit.unitConfig.ConditionFirstBoot = true;
            }
            {
              boot.initrd.systemd.services.systemd-journal-flush.serviceConfig.TimeoutSec = "10s";
            }
            {
              kdn.disks.persist."sys/cache" = {
                directories = [
                  "/var/cache"
                ];
              };
              home-manager.sharedModules = [
                {
                  kdn.disks.persist."sys/cache".directories = [ ".cache/nix" ];
                }
              ];
            }
            {
              kdn.disks.persist."sys/state" = {
                directories = [
                  "/var/lib/systemd/coredump"
                  "/var/log"
                  {
                    directory = "/var/log/journal";
                    inInitrd = true;
                  }
                ];
              };
            }
            {
              kdn.disks.persist."usr/config".files = [
                "/etc/nix/netrc"
                "/etc/nix/nix.sensitive.conf"
              ];
              home-manager.sharedModules = [
                {
                  kdn.disks.persist."usr/data".directories = [ ".local/share/nix" ];
                }
              ];
            }
            {
              home-manager.sharedModules = [
                {
                  kdn.disks.persist."usr/cache".directories = [
                    "Downloads"
                  ];
                  kdn.disks.persist."usr/data".directories = [
                    "Documents"
                    "Desktop"
                    "Pictures"
                    "Videos"
                  ];
                }
              ];
            }
            {
              disko.devices.nodev = {
                "/" = {
                  fsType = "tmpfs";
                  mountOptions = [
                    "size=${cfg.tmpfs.size}"
                    "mode=755"
                  ];
                };
                "/home" = {
                  fsType = "tmpfs";
                  mountOptions = [
                    "size=${cfg.tmpfs.size}"
                    "mode=755"
                  ];
                };
              };
            }
            # WARNING: keep build dir in sync with /modules/universal/nix.nix
            {
              systemd.tmpfiles.rules = [
                "L+ /nix/var/nix/builds           - - - - /nix/var/nix/builds-${cfg.nixBuildDir.type}"
              ];
              kdn.disks.persist."disposable".directories = [
                {
                  directory = "/nix/var/nix/builds-disposable";
                  mode = "0755";
                }
              ];
              disko.devices.nodev."/nix/var/nix/builds-tmpfs" = {
                fsType = "tmpfs";
                mountOptions = [
                  "size=${cfg.nixBuildDir.tmpfs.size}"
                  "mode=755"
                ];
              };
              disko.devices.zpool."${cfg.zpool-main.name}".datasets = {
                "${hostname}/nix-system/nix-builds" = {
                  type = "zfs_fs";
                  mountpoint = "/nix/var/nix/builds-zfs-dataset";
                  options.mountpoint = "/nix/var/nix/builds-zfs-dataset";
                  options."com.sun:auto-snapshot" = "false";
                  options.compression = "off";
                  options.atime = "off";
                  options.redundant_metadata = "none";
                  options.sync = "disabled";
                };
              };
            }
            {
              # required for kdn.disks.base.*.allowOther
              programs.fuse.userAllowOther = true;
            }
          ]
        ))
        {
          kdn.disks.disko.devices._meta = options.disko.devices.valueMeta.configuration.options._meta.default;
          disko.devices._meta = config.kdn.disks.disko.devices._meta;
        }
      ]
    ))
  ];
}
