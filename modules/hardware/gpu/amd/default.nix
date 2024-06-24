{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.gpu.amd;
in
{
  options.kdn.hardware.gpu.amd = {
    enable = lib.mkEnableOption "AMD GPU setup";
  };

  config = lib.mkIf cfg.enable {
    hardware.amdgpu.amdvlk.enable = true;
    hardware.amdgpu.amdvlk.support32Bit.enable = true;
    hardware.amdgpu.initrd.enable = true;
    hardware.amdgpu.opencl.enable = true;

    environment.systemPackages = with pkgs; [
      radeontop
    ];

    environment.variables.AMD_VULKAN_ICD = lib.mkDefault "RADV";
  };
}
