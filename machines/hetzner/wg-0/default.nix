{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  system.stateVersion = "21.11";
  networking.hostId = "550ded62"; # cut -c-8 </proc/sys/kernel/random/uuid
  networking.hostName = "wg-0";

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
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  boot.cleanTmpDir = true;


  # Hardware configuration goes below

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/39f735c2-b4aa-4412-b700-b7f3c1e88af7";
    fsType = "ext4";
  };
}
