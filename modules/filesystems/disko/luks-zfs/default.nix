{ config, pkgs, lib, modulesPath, waylandPkgs, ... }:
# Dell Latitude E5470
let
  cfg = config.kdn.profile.hardware.dell-e5470;
in
{
  options.kdn.filesystems.disko.luks-zfs = {
    enable = lib.mkEnableOption "enable setup using ZFS on LUKS2 set up using disko";
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
        disko = config.disko.devices;
        crypted = disko.disk.crypted-root;
        boot = disko.disk.boot;

        getArg = name: lib.trivial.pipe crypted.content.extraArgsFormat [
          (builtins.filter (lib.strings.hasPrefix "--${name}="))
          builtins.head
          (lib.strings.removePrefix "--${name}=")
        ];

        luksOpenName = crypted.content.name;
        rootUUID = getArg "uuid";
        headerPath = getArg "header";
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