{ config, pkgs, lib, modulesPath, ... }:
let
  cfg = config.kdn.filesystems.disko.luks-zfs;
in
{
  options.kdn.filesystems.disko.luks-zfs = {
    enable = lib.mkEnableOption "enable setup using ZFS on LUKS2 set up using disko";

    luksRoot = lib.mkOption {
      default = config.disko.devices.disko.disk.crypted-root;
      internal = true;
    };
    args = lib.mkOption {
      default = lib.trivial.pipe (cfg.luksRoot.content.extraFormatArgs or [ ]) [
        (builtins.filter (v: (builtins.match "--[^=]+=.+") v) != null)
        (builtins.map (builtins.match "--([^=]+)=(.+)"))
        (v: lib.attrsets.nameValuePair (builtins.elemAt v 0) (builtins.elemAt v 1))
        builtins.listToAttrs
      ];
      internal = true;
    };
  };

  config = lib.mkIf cfg.enable {
    kdn.filesystems.zfs.enable = true;

    boot.zfs.forceImportRoot = false;
    boot.zfs.requestEncryptionCredentials = false;

    # enables systemd-cryptsetup-generator
    # see https://github.com/nazarewk/nixpkgs/blob/04f574a1c0fde90b51bf68198e2297ca4e7cccf4/nixos/modules/system/boot/luksroot.nix#L997-L1012
    boot.initrd.luks.forceLuksSupportInInitrd = true;
    boot.initrd.systemd.enable = true;

    boot.kernelParams =
      let
        crypted = cfg.luksRoot;
        args = cfg.args;

        luksOpenName = crypted.content.name;
        rootUUID = args.uuid;
        headerPath = args.header;
        luksDevice = crypted.device;
      in
      [
        # https://www.freedesktop.org/software/systemd/man/systemd-cryptsetup-generator.html#
        "rd.luks.name=${rootUUID}=${luksOpenName}"
        "rd.luks.options=${rootUUID}=header=${headerPath}"
        "rd.luks.data=${rootUUID}=${luksDevice}"
      ];
    disko.enableConfig = true;

    fileSystems."/boot".neededForBoot = true;
    fileSystems."/var/log/journal".neededForBoot = true;
  };
}
