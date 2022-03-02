# https://nixos.wiki/wiki/AMD_GPU
{ config, pkgs, lib, modulesPath, ... }:
{
  system.stateVersion = "22.05";
  networking.hostId = "81d86976"; # cut -c-8 </proc/sys/kernel/random/uuid
  networking.hostName = "nazarewk-krul";

  nazarewk.sway.remote.enable = true;
  nazarewk.filesystems.zfs-root.enable = true;
  nazarewk.filesystems.zfs-root.sshUnlock.enable = true;
  hardware.cpu.amd.updateMicrocode = true;

  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./filesystem.nix
  ];

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.memtest86.enable = true;
  boot.loader.systemd-boot.configurationLimit = 20;

  boot.initrd.availableKernelModules = [
    "nvme" # NVMe disk
    "xhci_pci"
    "ahci"
    "usb_storage"
    "sd_mod"
    "r8169" # Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] (rev 05)
    "igb" # Intel Corporation I211 Gigabit Network Connection [8086:1539] (rev 03)
  ];
  boot.initrd.kernelModules = [ "amdgpu" "kvm-amd" ];
  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.opengl.enable = true;
  hardware.opengl.extraPackages = with pkgs; [
    amdvlk
    rocm-opencl-icd
    rocm-opencl-runtime
  ];
  hardware.opengl.extraPackages32 = with pkgs; [
    driversi686Linux.amdvlk
  ];
  hardware.opengl.driSupport = true;
  hardware.opengl.driSupport32Bit = true;
}