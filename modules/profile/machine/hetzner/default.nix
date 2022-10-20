{ config, pkgs, lib, modulesPath, waylandPkgs, ... }:
let
  cfg = config.kdn.profile.machine.hetzner;
in
{
  options.kdn.profile.machine.hetzner = {
    enable = lib.mkEnableOption "enable hetzner machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.baseline.enable = true;

    system.stateVersion = "22.11";

    # BOOT
    boot.kernelParams = [ "consoleblank=90" ];
    boot.initrd.availableKernelModules = [
      "ata_piix"
      "virtio_pci"
      "virtio_scsi"
      "xhci_pci"
      "sd_mod"
      "sr_mod"
    ];
    boot.kernelModules = [ ];
    boot.loader.grub.enable = true;
    boot.loader.grub.version = 2;
    boot.loader.grub.device = "/dev/sda";
    boot.cleanTmpDir = true;

    fileSystems."/" = {
      device = "/dev/sda1";
      fsType = "ext4";
    };
  };
}
