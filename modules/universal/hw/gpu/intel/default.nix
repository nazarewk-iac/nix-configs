{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.hw.gpu.intel;
in
{
  options.kdn.hw.gpu.intel = {
    enable = lib.mkEnableOption "intel GPU setup";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      # https://github.com/NixOS/nixos-hardware/blob/4045d5f43aff4440661d8912fc6e373188d15b5b/common/cpu/intel/default.nix
      # see https://github.com/NixOS/nixos-hardware/blob/0099253ad0b5283f06ffe31cf010af3f9ad7837d/common/gpu/intel.nix
      boot.initrd.kernelModules = [ "i915" ];

      kdn.env.variables = {
        VDPAU_DRIVER = lib.mkIf config.hardware.graphics.enable (lib.mkDefault "va_gl");
      };

      hardware.graphics.extraPackages = with pkgs; [
        # nixpkgs removed two aliases here. `vaapiIntel` is now `intel-vaapi-driver`, and
        # `vaapiVdpau` is now `libva-vdpau-driver`. Measured 2026-09-10: each alias stops the
        # evaluation of every host with an Intel GPU.
        intel-vaapi-driver # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
        libvdpau-va-gl
        libva-vdpau-driver
        intel-media-driver # LIBVA_DRIVER_NAME=iHD
      ];
    }
  );
}
