{ config, pkgs, lib, modulesPath, ... }:
# Dell Latitude E5470
let
  cfg = config.kdn.profile.hardware.dell-e5470;
in
{
  options.kdn.profile.hardware.dell-e5470 = {
    enable = lib.mkEnableOption "enable Dell Latitude E5470 tweaks";
  };

  config = lib.mkIf cfg.enable {
    #kdn.hardware.intel-graphics-fix.enable = true;
    kdn.hardware.modem.enable = true;

    # BOOT
    boot.initrd.availableKernelModules = [
      "rtsx_pci_sdmmc"
      "e1000e" # ethernet card
    ];
    boot.kernelModules = [ "kvm-intel" ];

    boot.initrd.kernelModules = [ "dm-snapshot" ];
    kdn.hardware.gpu.intel.enable = true;

    zramSwap.enable = true;
    zramSwap.memoryPercent = 50;
    zramSwap.priority = 100;
  };
}
