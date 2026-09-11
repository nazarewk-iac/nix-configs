# The Intel GPU setup, as a den aspect. It ports the `gpu/intel` module of the old hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It loads the `i915` driver from the initrd, and it adds the four VA-API and VDPAU drivers an Intel
# part needs.
#
# ## Class list: `nixos` alone
#
# The whole effect of the old module sits behind a `nixos` context guard, so the den aspect emits
# `nixos` only. Every driver package here is unsupported on Darwin, measured 2026-09-11.
#
# ## What the port changes
#
# **The native option replaces the cross-platform variable set.** A den target names its class, so
# this one writes `environment.sessionVariables`, which is what the old `kdn.env.variables` maps to
# on NixOS.
#
# ## Two aliases nixpkgs removed
#
# `vaapiIntel` is now `intel-vaapi-driver`, and `vaapiVdpau` is now `libva-vdpau-driver`. Measured
# 2026-09-10: each old alias stops the evaluation of every host with an Intel GPU.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. This aspect declares no option at all.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.hw-gpu-intel.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # See https://github.com/NixOS/nixos-hardware/blob/master/common/gpu/intel.nix
      boot.initrd.kernelModules = [ "i915" ];

      environment.sessionVariables.VDPAU_DRIVER = lib.mkIf config.hardware.graphics.enable (
        lib.mkDefault "va_gl"
      );

      hardware.graphics.extraPackages = with pkgs; [
        intel-vaapi-driver # LIBVA_DRIVER_NAME=i965, older but better for Firefox and Chromium
        libvdpau-va-gl
        libva-vdpau-driver
        intel-media-driver # LIBVA_DRIVER_NAME=iHD
      ];
    };
}
