{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.profile.host.oams;
in
{
  options.kdn.profile.host.oams = {
    enable = lib.mkEnableOption "enable oams host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.workstation.enable = true;
      kdn.hardware.gpu.amd.enable = true;

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

          getArg = name: lib.pipe crypted.content.extraArgsFormat [
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
      disko.devices = import ./disko.nix { inherit lib; };

      fileSystems."/boot".neededForBoot = true;
      fileSystems."/var/log/journal".neededForBoot = true;
      boot.kernelModules = ["kvm-amd"];

      services.asusd.enable = true;
      services.asusd.enableUserService = false; # just strobes the LEDs, better turn it off
      environment.systemPackages = with pkgs; [
        asusctl
        supergfxctl
      ];
    }
  ]);
}
