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

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # AMDVLK seems to break stuff? see https://matrix.to/#/!RRerllqmbATpmbJgCn:nixos.org/$E589UbXeIXAX76-k5EExVpxMkh_NsyDi5glqwqX5O18?via=lossy.network&via=matrix.org&via=tchncs.de
      #hardware.amdgpu.amdvlk.enable = lib.mkDefault true;
      #hardware.amdgpu.amdvlk.supportExperimental.enable = lib.mkDefault true;
      #hardware.amdgpu.amdvlk.support32Bit.enable = lib.mkDefault true;
      hardware.amdgpu.initrd.enable = lib.mkDefault true;

      environment.systemPackages = with pkgs; [
        radeontop
      ];

      #environment.variables.AMD_VULKAN_ICD = lib.mkDefault "RADV";
    }
    {
      /*
      OpenCL support:
      - is required for hardware acceleration support on Chromium browsers (Google Meet effects etc.)
      - force Mesa instead of ROCm , see https://matrix.to/#/!6oudZq5zJjAyrxL2uY:0upti.me/$F_B2Fq_H5_y6F8pjEpIydeZtu3Ybnip7g9A5xXMfvBc?via=laas.fr&via=matrix.org&via=envs.net
      - ROCm might be required for LLMs later on,
      */
      hardware.amdgpu.opencl.enable = false;
      hardware.graphics.extraPackages = with pkgs; [mesa.opencl];
    }
  ]);
}
