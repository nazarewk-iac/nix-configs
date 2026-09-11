# The Intel CPU setup, as a den aspect. It ports the `cpu/intel` module of the old hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns on the Intel microcode update and it loads the KVM module for an Intel part.
#
# ## Class list: `nixos` alone
#
# The whole old module sits behind a `nixos` context guard, so the den aspect emits `nixos` only.
#
# ## What the port changes
#
# **The aspect publishes `kdn.hw.cpu.intel.present`.** The old GPU module reads the `enable` flag of
# this module to decide one kernel parameter (`intel_iommu=on`). A den aspect has no `enable`, so
# inclusion is the only switch. This read-only leaf makes the inclusion readable: the GPU aspect
# reads `config.kdn.hw.cpu.intel.present or false`, and a class that omits this aspect declares no
# such option, so the read yields `false`.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. `present` is not an `enable`: it is read-only,
#    and it states a fact the consumer cannot change.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only.
{ ... }:
{
  kdn.hw-cpu-intel.nixos =
    { config, lib, ... }:
    {
      options.kdn.hw.cpu.intel.present = lib.mkOption {
        readOnly = true;
        type = lib.types.bool;
        default = true;
        description = ''
          This machine holds an Intel CPU. It is read-only, and it is `true` whenever this aspect is
          included.

          A sibling aspect reads `config.kdn.hw.cpu.intel.present or false`. A class that omits this
          aspect declares no such option, and the `or` then yields `false`.
        '';
      };

      config.hardware.cpu.intel.updateMicrocode =
        lib.mkDefault config.hardware.enableRedistributableFirmware;
      config.boot.kernelModules = [ "kvm-intel" ];
    };
}
