{ config, pkgs, lib, modulesPath, ... }:
let
  cfg = config.kdn.profile.machine.hetzner;
in
{
  options.kdn.profile.machine.hetzner = {
    enable = lib.mkEnableOption "enable hetzner machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.baseline.enable = true;

    # BOOT
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

    fileSystems."/" = {
      device = "/dev/sda1";
      fsType = "ext4";
    };
  };
}
