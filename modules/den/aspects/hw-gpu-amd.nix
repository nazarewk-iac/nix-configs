# The AMD GPU setup, as a den aspect. It ports the `gpu/amd` module of the old hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It loads the `amdgpu` driver from the initrd, it installs the AMD load monitor, and it takes the
# Mesa OpenCL implementation instead of ROCm.
#
# ## Class list: `nixos` alone
#
# The whole effect of the old module sits behind a `nixos` context guard, so the den aspect emits
# `nixos` only.
#
# ## What the port changes
#
# 1. **The aspect publishes `kdn.hw.gpu.amd.present`.** The generic GPU aspect reads the `enable`
#    flag of this module to decide one `supergfxd` kernel parameter. A den aspect has no `enable`, so
#    inclusion is the only switch. This read-only leaf makes the inclusion readable.
# 2. **The native option replaces the cross-platform package list.** A den target names its class,
#    so this one writes `environment.systemPackages`.
#
# ## Why OpenCL comes from Mesa
#
# Chromium needs OpenCL for hardware acceleration, for example for the video effects of a
# conference. ROCm answers that need too, but Mesa is the smaller and the more reliable route. See
# https://matrix.to/#/!6oudZq5zJjAyrxL2uY:0upti.me. ROCm may become necessary for a local language
# model later.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. `present` is not an `enable`: it is read-only,
#    and it states a fact the consumer cannot change.
# 3. **No custom module argument.** The target module below takes `lib` and `pkgs` only.
{ ... }:
{
  kdn.hw-gpu-amd.nixos =
    { lib, pkgs, ... }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      options.kdn.hw.gpu.amd.present = lib.mkOption {
        readOnly = true;
        type = lib.types.bool;
        default = true;
        description = ''
          This machine holds an AMD GPU. It is read-only, and it is `true` whenever this aspect is
          included.

          A sibling aspect reads `config.kdn.hw.gpu.amd.present or false`. A class that omits this
          aspect declares no such option, and the `or` then yields `false`.
        '';
      };

      config.environment.systemPackages = filterPackages [ pkgs.radeontop ];

      # AMDVLK breaks other software, so this aspect keeps the Mesa RADV driver. See
      # https://matrix.to/#/!RRerllqmbATpmbJgCn:nixos.org.
      config.hardware.amdgpu.initrd.enable = lib.mkDefault true;

      config.hardware.amdgpu.opencl.enable = false;
      config.hardware.graphics.extraPackages = [ pkgs.mesa.opencl ];
    };
}
