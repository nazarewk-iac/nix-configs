# TODO: add check not to be enabled on darwin?
{
  lib,
  pkgs,
  config,
  options,
  utils,
  ...
}: let
  cfg = config.kdn.disks;

  partSizeType = with lib.types; oneOf [str ints.positive];

  deviceType = lib.types.submodule (
    {name, ...} @ disk: {
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
        default = {};
      };
      options.partitions = lib.mkOption {
        default = {};
        type = lib.types.attrsOf (
          lib.types.submodule (
            {name, ...} @ part: {
              options.num = lib.mkOption {
                type = lib.types.ints.between 1 128;
              };
              options.path = lib.mkOption {
                internal = true;
                type = lib.types.path;
                default = let
                  path = disk.config.path;
                  partNum = builtins.toString part.config.num;
                in
                  if lib.strings.hasPrefix "/dev/disk/" path
                  then "${path}-part${partNum}"
                  else if (builtins.match "/dev/[^/]+" path) != null
                  then "${path}${partNum}"
                  else builtins.throw "Don't know how to generate partition number for disk ${path}";
              };
              options.size = lib.mkOption {
                type = partSizeType;
              };
              options.disko = lib.mkOption {
                default = {};
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
    } @ partSel: {
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
        default = let
          key = partSel.config.deviceKey;
        in
          cfg.devices."${key}";
      };
      options.partition = lib.mkOption {
        type = with lib.types; anything;
        default = with partSel.config;
          if partitionKey == null
          then {}
          else device.partitions."${partitionKey}";
      };
      options.path = lib.mkOption {
        internal = true;
        type = lib.types.path;
        default =
          if partSel.config.partition == {}
          then partSel.config.device.path
          else partSel.config.partition.path;
      };
    }
  );
in {
  imports = [
    (
      lib.mkRenamedOptionModule
      ["kdn" "hw" "disks"]
      ["kdn" "disks"]
    )
  ];
  options.kdn.disks = {
    enable = lib.mkOption {
      description = "enable persistence@ZFS@LUKS-volumes with detached headers and separate /boot";
      type = lib.types.bool;
      default = false;
      apply = value:
        assert lib.assertMsg (!(value && config.kdn.fs.disko.luks-zfs.enable)) ''
          You must choose only one of: `kdn.disks.enable` or `kdn.fs.disko.luks-zfs.enable`, not both!
        ''; value;
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
      default = {};
      type = lib.types.attrsOf (
        lib.types.submodule (
          {name, ...} @ userArgs: {
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
      description = ''which disks config should $HOME come from?'';
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
      default = {};
    };
    luks.volumes = lib.mkOption {
      default = {};
      type = lib.types.attrsOf (
        lib.types.submodule (
          {name, ...} @ luksVol: {
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
              default = {};
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
      default = {};
      type = lib.types.attrsOf (
        lib.types.submodule (
          {name, ...} @ zpool: {
            options.disko = lib.mkOption {
              default = {};
            };
            options.import.timeout = lib.mkOption {
              type = with lib.types; int;
              default = 15;
            };
            options.cryptsetup.requires = lib.mkOption {
              type = with lib.types; listOf str;
              default = [];
            };
            options.cryptsetup.names = lib.mkOption {
              type = with lib.types; listOf str;
              default = lib.trivial.pipe cfg.luks.volumes [
                (lib.filterAttrs (luksVolName: luksVol: luksVol.zpool.name == zpool.name))
                (builtins.mapAttrs (luksVolName: luksVol: luksVol.name))
                builtins.attrValues
                (builtins.map (luksName: "systemd-cryptsetup@${utils.escapeSystemdPath luksName}"))
              ];
            };
            options.cryptsetup.services = lib.mkOption {
              type = with lib.types; listOf str;
              default = builtins.map (name: "${name}.service") zpool.config.cryptsetup.names;
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
      default = {};
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.directories = lib.mkOption {
            type = lib.types.listOf (
              lib.types.either lib.types.str (
                lib.types.submodule {freeformType = (pkgs.formats.json {}).type;}
              )
            );
            default = [];
          };
          options.files = lib.mkOption {
            type = lib.types.listOf (
              lib.types.either lib.types.str (
                lib.types.submodule {freeformType = (pkgs.formats.json {}).type;}
              )
            );
            default = [];
          };
          options.users = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                freeformType = (pkgs.formats.json {}).type;
                options.directories = lib.mkOption {
                  type = lib.types.listOf (
                    lib.types.either lib.types.str (
                      lib.types.submodule {freeformType = (pkgs.formats.json {}).type;}
                    )
                  );
                  default = [];
                };
                options.files = lib.mkOption {
                  type = lib.types.listOf (
                    lib.types.either lib.types.str (
                      lib.types.submodule {freeformType = (pkgs.formats.json {}).type;}
                    )
                  );
                  default = [];
                };
              }
            );
            default = {};
          };
        }
      );
    };
    base = lib.mkOption {
      default = {};
      type = lib.types.attrsOf (
        lib.types.submodule (
          {name, ...} @ baseArgs: let
            baseCfg = baseArgs.config;
          in {
            options.neededForBoot = lib.mkOption {
              type = with lib.types; listOf path;
              default = [];
              apply = ls: ["${baseCfg.mountpoint}"] ++ ls;
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
              default = {};
            };
          }
        )
      );
    };
    disko.devices._meta = lib.mkOption {
      type = (pkgs.formats.json {}).type;
      default = {};
    };
    disko.debug = lib.mkOption {
      readOnly = true;
      default = let
        diskoLib = pkgs.lib.disko;
        cfg.config = config.disko.devices;
        # https://github.com/nix-community/disko/blob/5a88a6eceb8fd732b983e72b732f6f4b8269bef3/lib/default.nix#L644-L653
        devices = {
          inherit
            (cfg.config)
            bcachefs_filesystems
            disk
            mdadm
            zpool
            lvm_vg
            nodev
            ;
        };
        # https://github.com/nix-community/disko/blob/5a88a6eceb8fd732b983e72b732f6f4b8269bef3/lib/default.nix#L992-L993
        sortedDeviceList =
          diskoLib.sortDevicesByDependencies (
            cfg.config._meta.deviceDependencies or {}
          )
          devices;
      in
        if config ? disko
        then {
          inherit
            (cfg.config._meta)
            deviceDependencies
            ;
          inherit
            cfg
            diskoLib
            devices
            sortedDeviceList
            ;
        }
        else {};
    };
  };
}
