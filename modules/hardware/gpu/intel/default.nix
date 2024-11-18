{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hardware.gpu.intel;
in {
  options.kdn.hardware.gpu.intel = {
    enable = lib.mkEnableOption "intel GPU setup";
  };

  config = lib.mkIf cfg.enable {
    # https://github.com/NixOS/nixos-hardware/blob/4045d5f43aff4440661d8912fc6e373188d15b5b/common/cpu/intel/default.nix
    # see https://github.com/NixOS/nixos-hardware/blob/0099253ad0b5283f06ffe31cf010af3f9ad7837d/common/gpu/intel.nix
    boot.initrd.kernelModules = ["i915"];

    environment.variables = {
      VDPAU_DRIVER = lib.mkIf config.hardware.graphics.enable (lib.mkDefault "va_gl");
    };

    hardware.graphics.extraPackages = with pkgs; [
      vaapiIntel # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
      libvdpau-va-gl
      vaapiVdpau
      intel-media-driver # LIBVA_DRIVER_NAME=iHD
    ];
  };
}
