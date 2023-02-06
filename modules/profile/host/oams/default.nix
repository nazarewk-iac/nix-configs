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
      kdn.networking.netbird.instances.w1 = 51822;
      kdn.profile.machine.workstation.enable = true;
      kdn.hardware.gpu.amd.enable = true;

      boot.zfs.forceImportRoot = false;
      boot.zfs.requestEncryptionCredentials = false;

      # enables systemd-cryptsetup-generator
      # see https://github.com/nazarewk/nixpkgs/blob/04f574a1c0fde90b51bf68198e2297ca4e7cccf4/nixos/modules/system/boot/luksroot.nix#L997-L1012
      boot.initrd.luks.forceLuksSupportInInitrd = true;
      boot.initrd.systemd.enable = true;

      kdn.filesystems.disko.luks-zfs.enable = true;
      disko.devices = import ./disko.nix { inherit lib; };
      boot.kernelModules = [ "kvm-amd" ];

      services.asusd.enable = true;
      services.asusd.enableUserService = false; # just strobes the LEDs, better turn it off
      environment.systemPackages = with pkgs; [
        asusctl
        supergfxctl
      ];

      services.transmission = {
        enable = true;
      };
    }
  ]);
}
