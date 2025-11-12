# it's in universal to work around kdn.disks
{
  config,
  pkgs,
  lib,
  utils,
  ...
}: let
  cfg = config.kdn.fs.disko.luks-zfs;
in {
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
      default = [];
    };

    luksNames = lib.mkOption {
      type = with lib.types; listOf str;
      default = lib.trivial.pipe ((config.disko or {}).devices or {}) [
        (lib.attrsets.filterAttrsRecursive (n: v: !(lib.strings.hasPrefix "_" n)))
        (lib.collect (
          v:
            (v.type or "")
            == "luks"
            && (v ? name)
            && (v.content.type or "") == "zfs"
            && (v.content.pool or "") == cfg.poolName
        ))
        (builtins.map (v: v.name))
        (
          v:
            assert lib.assertMsg (v != []) ''
              disko configuration for ZFS on LUKS not found, required structure is:
                - .type == "luks"
                - .content.type == "zfs"
                - .content.pool == "${cfg.poolName}"
            ''; v
        )
      ];
    };

    cryptsetupNames = lib.mkOption {
      default =
        builtins.map (
          luksName: "systemd-cryptsetup@${utils.escapeSystemdPath luksName}"
        )
        cfg.luksNames;
    };
  };
}
