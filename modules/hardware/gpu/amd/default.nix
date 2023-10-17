{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.gpu.amd;
in
{
  options.kdn.hardware.gpu.amd = {
    enable = lib.mkEnableOption "AMD GPU setup";
  };

  config = lib.mkIf cfg.enable {
    # see https://github.com/NixOS/nixos-hardware/blob/0099253ad0b5283f06ffe31cf010af3f9ad7837d/common/gpu/amd/default.nix
    # see https://github.com/nixos-rocm/nixos-rocm
    #boot.kernelModules = [ "amdgpu" ];
    #services.xserver.videoDrivers = [ "amdgpu" ];

    hardware.opengl.enable = true;
    hardware.opengl.extraPackages = with pkgs; [
      amdvlk
    ] ++ (with pkgs.rocmPackages;[
      clr
      clr.icd
    ]);

    hardware.opengl.extraPackages32 = with pkgs; [
      # TODO: 2023-02-16: broken due to below
      #  Failed to compile Vulkan shader config ShaderConfig< Path: RadixSort/ScanExclusiveInt4DLB.hlsl, EntryPoint: InitScanExclusiveInt4DLB, OutputName: None, BaseLogicalId: None, RootSignaturePath: None, Defines: None, GroupTag: BVH >
      #  Compilation failed for shader DeserializeAS
      # see https://github.com/NixOS/nixpkgs/pull/216465
      # see https://github.com/NixOS/nixpkgs/issues/216294
      # driversi686Linux.amdvlk # see above
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
