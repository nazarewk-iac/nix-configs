{ lib, pkgs, config, options, utils, ... }:
let
  cfg = config.kdn.hardware.disks;
  hostname = config.networking.hostName;

  deviceType = lib.types.submodule ({ name, ... }@disk: {
    options.type = lib.mkOption {
      type = lib.types.enum [ "gpt" "luks" ];
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
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@part: {
        options.num = lib.mkOption {
          type = lib.types.ints.between 1 128;
        };
        options.path = lib.mkOption {
          internal = true;
          type = lib.types.path;
          default = "${disk.config.path}-part${builtins.toString part.config.num}";
        };
        options.size = lib.mkOption {
          type = lib.types.ints.positive;
        };
        options.disko = lib.mkOption {
          default = { };
        };
      }));
    };
  });

  deviceSelectorType = lib.types.submodule ({ name, config, ... }@partSel: {
    options.deviceKey = lib.mkOption {
      type = lib.types.str;
    };
    options.partitionKey = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };
    options.device = lib.mkOption {
      type = deviceType;
      internal = true;
      default =
        let key = partSel.config.deviceKey; in
        cfg.devices."${key}";
    };
    options.partition = lib.mkOption {
      type = with lib.types; anything;
      default =
        with partSel.config;
        if partitionKey == null then { }
        else device.partitions."${partitionKey}";
    };
    options.path = lib.mkOption {
      internal = true;
      type = lib.types.path;
      default =
        if partSel.config.partition == { }
        then partSel.config.device.path
        else partSel.config.partition.path;
    };
  });
in
{
  imports = [
    ./default-configs.nix
    ./handle-options.nix
  ];
  options.kdn.hardware.disks = {
    enable = lib.mkOption {
      description = "enable impermanence@ZFS@LUKS-volumes with detached headers and separate /boot";
      type = lib.types.bool;
      default = false;
      apply = value: assert lib.assertMsg (!(value && config.kdn.filesystems.disko.luks-zfs.enable)) ''
        You must choose only one of: `kdn.hardware.disks.enable` or `kdn.filesystems.disko.luks-zfs.enable`, not both!
      ''; value;
    };

    luks.header.size = lib.mkOption {
      type = lib.types.ints.u8;
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
      default = "${config.networking.hostName}-main";
    };
    initrd.failureTarget = lib.mkOption {
      type = lib.types.str;
      default = "emergency.target";
    };
    initrd.emergency.rebootTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
    };

    devices = lib.mkOption {
      type = lib.types.attrsOf deviceType;
      default = { };
    };
    luks.volumes = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@luksVol: {
        options.target = lib.mkOption {
          type = deviceSelectorType;
        };
        options.targetSpec.path = lib.mkOption {
          type = with lib.types; nullOr path;
        };
        options.uuid = lib.mkOption {
          type = lib.types.str;
        };
        options.keyFile = lib.mkOption {
          type = with lib.types; nullOr str;
          /* configuring disko's `settings.keyFile` puts the keyFile in the systemd service
              preventing it from working with TPM2/YubiKey etc.
          */
          default = "/tmp/${luksVol.name}.key";
        };
        options.header = lib.mkOption {
          type = deviceSelectorType;
        };
        options.headerSpec.num = lib.mkOption {
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
          target.partitionKey = null;
          header.deviceKey = lib.mkDefault "boot";
          header.partitionKey = lib.mkDefault "${luksVol.name}-header";
        };
      }));
    };
    zpools = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@zpool: {
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
      }));
    };
    impermanence = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@imp: {
        options.neededForBoot = lib.mkOption {
          type = with lib.types; listOf path;
          default = [ ];
          apply = ls: [ "${imp.config.mountpoint}" ] ++ ls;
        };
        options.mountpoint = lib.mkOption {
          type = with lib.types; path;
          default = "${imp.config.mountPrefix}/${imp.name}";
        };
        options.mountPrefix = lib.mkOption {
          type = with lib.types; path;
          default = "/nix/persist";
        };
        options.zfsPrefix = lib.mkOption {
          type = with lib.types; str;
          default = "${hostname}/impermanence";
        };
        options.zfsPath = lib.mkOption {
          type = with lib.types; str;
          default = "${imp.config.zfsPrefix}/${imp.name}";
        };
        options.zpool.name = lib.mkOption {
          type = with lib.types; nullOr str;
          default = cfg.zpool-main.name;
        };
        options.snapshots = lib.mkOption {
          type = with lib.types; bool;
        };
      }));
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (!cfg.enable) {
      environment.persistence = lib.mkForce { };
      home-manager.sharedModules = [{ home.persistence = lib.mkForce { }; }];
    })
    # the rest of configs are in ./handle-options.nix
    (lib.mkIf cfg.enable {
      # enables systemd-cryptsetup-generator
      # see https://github.com/nazarewk/nixpkgs/blob/04f574a1c0fde90b51bf68198e2297ca4e7cccf4/nixos/modules/system/boot/luksroot.nix#L997-L1012
      boot.initrd.luks.forceLuksSupportInInitrd = true;
      boot.initrd.systemd.enable = true;

      disko.enableConfig = true;
      kdn.filesystems.zfs.enable = true;
      kdn.security.disk-encryption.enable = true;
      boot.zfs.requestEncryptionCredentials = false;
    })
  ];
}
