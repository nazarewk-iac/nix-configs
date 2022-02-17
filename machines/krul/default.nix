# https://nixos.wiki/wiki/AMD_GPU
{ config, pkgs, lib, modulesPath, ... }:
{
  system.stateVersion = "22.05";
  networking.hostId = "81d86976"; # cut -c-8 </proc/sys/kernel/random/uuid
  networking.hostName = "nazarewk-krul";

  nazarewk.filesystems.zfs-root.enable = true;
  hardware.cpu.amd.updateMicrocode = true;

  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./filesystem.nix
  ];

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.memtest86.enable = true;

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