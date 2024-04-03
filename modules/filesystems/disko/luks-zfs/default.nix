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

    luks = lib.mkOption {
      default = lib.trivial.pipe cleanDisko [
        (lib.collect (v:
          (v.type or "") == "luks"
          && (v ? name)
          && (v.content.type or "") == "zfs"
          && (v.content.pool or "") == cfg.poolName
        ))
        (v: assert lib.assertMsg (v != [ ]) ''
          disko configuration for ZFS on LUKS not found, required structure is:
            - .type == "luks"
            - .content.type == "zfs"
            - .content.pool == "${cfg.poolName}"
        ''; v)
        builtins.head
      ];
      internal = true;
    };
    luksArgs = lib.mkOption {
      default = lib.trivial.pipe (cfg.luks.extraFormatArgs or [ ]) [
        (builtins.filter (v: (builtins.match "--[^=]+=.+") v != null))
        (builtins.map (builtins.match "--([^=]+)=(.+)"))
        (builtins.map (v: lib.attrsets.nameValuePair (builtins.elemAt v 0) (builtins.elemAt v 1)))
        builtins.listToAttrs
      ];
      internal = true;
      apply = args: assert lib.assertMsg (args ? uuid) ''
        `--uuid=XXXXX` argument is missing from `.type.extraFormatArgs` on `kdn.filesystems.disko.luks-zfs.luks`.
      ''; args;
    };

    luksHeader = lib.mkOption {
      default =
        if cfg.luksArgs ? header then cfg.luksArgs.header
        else if cfg.luks.content ? settings && cfg.luks.content.settings ? header then cfg.luks.content.settings.header
        else null;
      internal = true;
    };

    cryptsetupName = lib.mkOption {
      default = "systemd-cryptsetup@${utils.escapeSystemdPath cfg.luks.name}";
      internal = true;
    };
  };

  config = lib.mkIf cfg.enable {
    kdn.filesystems.zfs.enable = true;

    boot.zfs.forceImportRoot = false;
    boot.zfs.extraPools = [ cfg.poolName ];
    boot.zfs.requestEncryptionCredentials = false;

    # enables systemd-cryptsetup-generator
    # see https://github.com/nazarewk/nixpkgs/blob/04f574a1c0fde90b51bf68198e2297ca4e7cccf4/nixos/modules/system/boot/luksroot.nix#L997-L1012
    boot.initrd.luks.forceLuksSupportInInitrd = true;
    boot.initrd.systemd.enable = true;

    disko.enableConfig = true;

    boot.initrd.systemd.services."${cfg.cryptsetupName}" = {
      overrideStrategy = "asDropin";
      requires = cfg.decryptRequiresUnits;
      after = cfg.decryptRequiresUnits;
      wants = [ "systemd-udev-settle.service" ];
      onFailure = [ "emergency.target" ];
      serviceConfig.TimeoutSec = cfg.timeout;
    };

    boot.initrd.systemd.services."zfs-import-${cfg.poolName}" = {
      requires = [ "${cfg.cryptsetupName}.service" ];
      requiredBy = [ "initrd-fs.target" ];
      onFailure = [ "emergency.target" ];
      serviceConfig.TimeoutSec = cfg.timeout;
    };

    fileSystems."/boot".neededForBoot = true;
    fileSystems."/var/log/journal".neededForBoot = true;
  };
}
