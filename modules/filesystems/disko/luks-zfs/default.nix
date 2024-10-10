{ config, pkgs, lib, utils, modulesPath, ... }:
let
  cfg = config.kdn.filesystems.disko.luks-zfs;

  cleanDisko = lib.attrsets.filterAttrsRecursive (n: v: !(lib.strings.hasPrefix "_" n)) config.disko.devices;
in
{
  options.kdn.filesystems.disko.luks-zfs = {
    enable = lib.mkEnableOption "enable setup using ZFS on LUKS2 set up using disko";

    timeout = lib.mkOption {
      type = with lib.types; int;
      default = 15;
    };

    poolName = lib.mkOption {
      default = "${config.networking.hostName}-main";
      internal = true;
    };

    decryptRequiresUnits = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };

    luksNames = lib.mkOption {
      type = with lib.types; listOf str;
      default = lib.trivial.pipe cleanDisko [
        (lib.collect (v:
          (v.type or "") == "luks"
          && (v ? name)
          && (v.content.type or "") == "zfs"
          && (v.content.pool or "") == cfg.poolName
        ))
        (builtins.map (v: v.name))
        (v: assert lib.assertMsg (v != [ ]) ''
          disko configuration for ZFS on LUKS not found, required structure is:
            - .type == "luks"
            - .content.type == "zfs"
            - .content.pool == "${cfg.poolName}"
        ''; v)
      ];
    };

    cryptsetupNames = lib.mkOption {
      default = builtins.map (luksName: "systemd-cryptsetup@${utils.escapeSystemdPath luksName}") cfg.luksNames;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.filesystems.zfs.enable = true;

      boot.zfs.forceImportRoot = false;
      boot.zfs.extraPools = [ cfg.poolName ];
      boot.zfs.requestEncryptionCredentials = false;

      # enables systemd-cryptsetup-generator
      # see https://github.com/nazarewk/nixpkgs/blob/04f574a1c0fde90b51bf68198e2297ca4e7cccf4/nixos/modules/system/boot/luksroot.nix#L997-L1012
      boot.initrd.luks.forceLuksSupportInInitrd = true;
      boot.initrd.systemd.enable = true;

      disko.enableConfig = true;

      boot.initrd.systemd.services."zfs-import-${cfg.poolName}" = {
        requires = builtins.map (name: "${name}.service") cfg.cryptsetupNames;
        after = builtins.map (name: "${name}.service") cfg.cryptsetupNames;
        requiredBy = [ "initrd-fs.target" ];
        onFailure = [ "rescue.target" ];
        serviceConfig.TimeoutSec = cfg.timeout;
      };

      fileSystems."/boot".neededForBoot = true;
      fileSystems."/var/log/journal".neededForBoot = true;
    }
    {
      boot.initrd.systemd.services = lib.pipe cfg.cryptsetupNames [
        (builtins.map (name: {
          inherit name;
          value = {
            overrideStrategy = "asDropin";
            requires = cfg.decryptRequiresUnits;
            after = cfg.decryptRequiresUnits;
            wants = [ "systemd-udev-settle.service" ];
            onFailure = [ "rescue.target" ];
            serviceConfig.TimeoutSec = cfg.timeout;
          };
        }))
        builtins.listToAttrs
      ];
    }
  ]);
}
