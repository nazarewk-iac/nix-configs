{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.hardware.gpu.amd;
in
{
  options.kdn.hardware.gpu.amd = {
    enable = lib.mkEnableOption "AMD GPU setup";
  };

  config = mkIf cfg.enable {
    # see https://github.com/NixOS/nixos-hardware/blob/0099253ad0b5283f06ffe31cf010af3f9ad7837d/common/gpu/amd/default.nix
    # see https://github.com/nixos-rocm/nixos-rocm
    boot.kernelModules = [ "amdgpu" ];
    services.xserver.videoDrivers = [ "amdgpu" ];

    hardware.opengl.enable = true;
    hardware.opengl.extraPackages = with pkgs; [
      rocm-opencl-icd
      rocm-opencl-runtime
      amdvlk
    ];

    hardware.opengl.extraPackages32 = with pkgs; [
      driversi686Linux.amdvlk
    ];

    hardware.opengl = {
      driSupport = lib.mkDefault true;
      driSupport32Bit = lib.mkDefault true;
    };

    environment.systemPackages = with pkgs; [
      radeontop
    ];

    environment.variables.AMD_VULKAN_ICD = lib.mkDefault "RADV";
  };
}
