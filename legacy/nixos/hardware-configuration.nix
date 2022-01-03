# this was only initially generated, now is managed
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "uas" "rtsx_pci_sdmmc" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "nazarewk-zroot/nazarewk/root";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/34E7-0AA1";
    fsType = "vfat";
  };

  fileSystems."/home" = {
    device = "nazarewk-zroot/nazarewk/home";
    fsType = "zfs";
  };

  fileSystems."/home/nazarewk" = {
    device = "nazarewk-zroot/nazarewk/home/nazarewk";
    fsType = "zfs";
  };

  fileSystems."/home/nazarewk/Downloads" = {
    device = "nazarewk-zroot/nazarewk/home/nazarewk/Downloads";
    fsType = "zfs";
  };

  fileSystems."/home/nazarewk/Nextcloud" = {
    device = "nazarewk-zroot/nazarewk/home/nazarewk/Nextcloud";
    fsType = "zfs";
  };

  fileSystems."/nix" = {
    device = "nazarewk-zroot/local/nix";
    fsType = "zfs";
  };

  fileSystems."/var" = {
    device = "nazarewk-zroot/nazarewk/var";
    fsType = "zfs";
  };

  fileSystems."/var/log" = {
    device = "nazarewk-zroot/nazarewk/var/log";
    fsType = "zfs";
  };

  fileSystems."/var/log/journal" = {
    device = "nazarewk-zroot/nazarewk/var/log/journal";
    fsType = "zfs";
  };

  fileSystems."/tmp" = {
    device = "nazarewk-zroot/nazarewk/tmp";
    fsType = "zfs";
  };

  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;
  zramSwap.priority = 100;

  swapDevices = [
    {
      device = "/dev/disk/by-partuuid/efd708db-6eb2-48ef-82c0-7760c1f3dd3e";
      priority = -10;
      randomEncryption.enable = true;
    }
  ];

  powerManagement.cpuFreqGovernor = "performance";

  hardware.cpu.intel.updateMicrocode = true;
  boot.initrd.kernelModules = [ "dm-snapshot" "i915" ];
  # https://github.com/NixOS/nixos-hardware/blob/4045d5f43aff4440661d8912fc6e373188d15b5b/common/cpu/intel/default.nix
  hardware.opengl.extraPackages = with pkgs; [
    intel-media-driver # LIBVA_DRIVER_NAME=iHD
    vaapiIntel # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
    vaapiVdpau
    libvdpau-va-gl
  ];
}
