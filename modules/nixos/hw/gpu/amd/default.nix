{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hw.gpu.amd;
in {
  options.kdn.hw.gpu.amd = {
    enable = lib.mkEnableOption "AMD GPU setup";
  };

  config = lib.mkIf cfg.enable {
    hardware.amdgpu.amdvlk.enable = lib.mkDefault true;
    hardware.amdgpu.amdvlk.support32Bit.enable = lib.mkDefault true;
    hardware.amdgpu.initrd.enable = lib.mkDefault true;
    hardware.amdgpu.opencl.enable = lib.mkDefault true;

    environment.systemPackages = with pkgs; [
      radeontop
    ];

    environment.variables.AMD_VULKAN_ICD = lib.mkDefault "RADV";
  };
}
