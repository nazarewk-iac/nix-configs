{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.kdn.fs.disko.luks-zfs;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.fs.zfs.enable = true;

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
    ]
  );
}
