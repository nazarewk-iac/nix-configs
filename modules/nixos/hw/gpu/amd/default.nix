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
    # AMDVLK seems to break stuff? see https://matrix.to/#/!RRerllqmbATpmbJgCn:nixos.org/$E589UbXeIXAX76-k5EExVpxMkh_NsyDi5glqwqX5O18?via=lossy.network&via=matrix.org&via=tchncs.de
    #hardware.amdgpu.amdvlk.enable = lib.mkDefault true;
    #hardware.amdgpu.amdvlk.supportExperimental.enable = lib.mkDefault true;
    #hardware.amdgpu.amdvlk.support32Bit.enable = lib.mkDefault true;
    hardware.amdgpu.initrd.enable = lib.mkDefault true;
    hardware.amdgpu.opencl.enable = lib.mkDefault true;

    environment.systemPackages = with pkgs; [
      radeontop
    ];

    #environment.variables.AMD_VULKAN_ICD = lib.mkDefault "RADV";
  };
}
