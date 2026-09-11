# The Dell Latitude E5470 profile of the old hardware area, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It loads the four kernel modules this laptop needs, and it turns zram swap on at 50 percent.
# It also pulls in the Intel GPU aspect and the modem aspect.
#
# ## Class list: `nixos` alone
#
# The whole effect of the old module sits behind a `nixos` context guard. The laptop runs NixOS.
#
# ## What the port changes
#
# 1. **The `enable` option goes.** Inclusion is the switch.
# 2. **The two `enable` writes become `includes` entries.** The old module writes
#    `kdn.hw.modem.enable` and `kdn.hw.gpu.intel.enable`, each as `lib.mkDefault true`. den collapses
#    a diamond, so another aspect may name the same two.
#
# ## One commented line stays out
#
# The old module holds `#kdn.hw.intel-graphics-fix.enable = true;` as a comment. A comment is not
# behaviour, so this aspect does not include `hw-intel-graphics-fix`. A host that needs the fix
# includes that aspect itself.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. This aspect declares no option at all.
# 3. **No custom module argument.** The target module below takes `lib` only.
{ kdn, ... }:
{
  kdn.hw-dell-e5470.includes = [
    kdn.hw-gpu-intel
    kdn.hw-modem
  ];

  kdn.hw-dell-e5470.nixos =
    { lib, ... }:
    {
      boot.initrd.availableKernelModules = [
        "rtsx_pci_sdmmc"
        "e1000e" # ethernet card
      ];
      boot.kernelModules = [ "kvm-intel" ];
      boot.initrd.kernelModules = [ "dm-snapshot" ];

      zramSwap.enable = lib.mkDefault true;
      zramSwap.memoryPercent = 50;
      zramSwap.priority = 100;
    };
}
