# it's in universal to work around kdn.disks
{
  config,
  pkgs,
  lib,
  utils ? null,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.fs.disko.luks-zfs;
in
{
  options.kdn.fs.disko.luks-zfs = {
    enable = lib.mkEnableOption "enable setup using ZFS on LUKS2 set up using disko";

    timeout = lib.mkOption {
      type = with lib.types; int;
      default = 15;
    };

    poolName = lib.mkOption {
      default = "${config.kdn.hostName}-main";
      internal = true;
    };

    decryptRequiresUnits = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };

    luksNames = lib.mkOption {
      type = with lib.types; listOf str;
      default = lib.trivial.pipe ((config.disko or { }).devices or { }) [
        (lib.attrsets.filterAttrsRecursive (n: v: !(lib.strings.hasPrefix "_" n)))
        (lib.collect (
          v:
          (v.type or "") == "luks"
          && (v ? name)
          && (v.content.type or "") == "zfs"
          && (v.content.pool or "") == cfg.poolName
        ))
        (map (v: v.name))
        (
          v:
          assert lib.assertMsg (v != [ ]) ''
            disko configuration for ZFS on LUKS not found, required structure is:
              - .type == "luks"
              - .content.type == "zfs"
              - .content.pool == "${cfg.poolName}"
          '';
          v
        )
      ];
    };

    cryptsetupNames = lib.mkOption {
      default = map (luksName: "systemd-cryptsetup@${utils.escapeSystemdPath luksName}") cfg.luksNames;
    };
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.fs.zfs.enable = true;

          boot.zfs.forceImportRoot = false;
          boot.zfs.extraPools = [ cfg.poolName ];
          boot.zfs.requestEncryptionCredentials = false;

          boot.initrd.luks.forceLuksSupportInInitrd = true;
          boot.initrd.systemd.enable = true;

          disko.enableConfig = true;

          boot.initrd.systemd.services."zfs-import-${cfg.poolName}" = {
            requires = map (name: "${name}.service") cfg.cryptsetupNames;
            after = map (name: "${name}.service") cfg.cryptsetupNames;
            requiredBy = [ "initrd-fs.target" ];
            onFailure = [ "emergency.target" ];
            serviceConfig.TimeoutSec = cfg.timeout;
          };

          fileSystems."/boot".neededForBoot = true;
          fileSystems."/var/log/journal".neededForBoot = true;
        }
        {
          boot.initrd.systemd.services = lib.pipe cfg.cryptsetupNames [
            (map (name: {
              inherit name;
              value = {
                overrideStrategy = "asDropin";
                requires = cfg.decryptRequiresUnits;
                after = cfg.decryptRequiresUnits;
                wants = [ "systemd-udev-settle.service" ];
                onFailure = [ "emergency.target" ];
                serviceConfig.TimeoutSec = cfg.timeout;
              };
            }))
            builtins.listToAttrs
          ];
        }
      ]
    )
  );
}
