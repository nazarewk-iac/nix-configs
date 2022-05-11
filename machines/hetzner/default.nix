{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
  ];

  system.stateVersion = "21.11";

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
}
