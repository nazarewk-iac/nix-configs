# The AMD CPU setup, as a den aspect. It ports the `cpu/amd` module of the old hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns on the AMD microcode update, the Ryzen SMU kernel driver and the SEV memory-encryption
# support. It installs two tools that read and write the power limits of a Ryzen part.
#
# ## Class list: `nixos` alone
#
# The whole old module sits behind a `nixos` context guard, so the den aspect emits `nixos` only.
#
# ## What the port changes
#
# **The native option replaces the cross-platform package list.** A den target names its class, so
# this one writes `environment.systemPackages`. The `apply` filter moves to
# ../common/filter-packages.nix.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.hw-cpu-amd.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      # `ryzenadj` reports "Error accessing SMU: SMU Driver Version Incompatible With Library
      # Version" when the kernel driver and the library disagree.
      environment.systemPackages = filterPackages (
        with pkgs;
        [
          ryzenadj
          amdctl
        ]
      );

      hardware.cpu.amd.ryzen-smu.enable = true;
      hardware.cpu.amd.sev.enable = true;
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      programs.ryzen-monitor-ng.enable = true;
    };
}
