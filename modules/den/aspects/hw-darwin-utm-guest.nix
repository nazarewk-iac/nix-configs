# The UTM guest profile of the old hardware area, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It imports the nixpkgs QEMU guest profile, and it adds the two initrd modules a UTM disk needs.
#
# ## Class list: `nixos` alone
#
# The whole effect of the old module sits behind a `nixos` context guard. A UTM guest is a NixOS
# virtual machine on a Darwin host, so no other class applies.
#
# ## What the port changes
#
# 1. **The `enable` option goes, and so does the feature flag.** The old option reads
#    `kdnConfig.features.darwin-utm-guest`, and the `imports` list reads the same flag. In den the
#    flag disappears: inclusion is the switch. A host that is a UTM guest includes this aspect.
# 2. **The conditional `imports` becomes an unconditional one.** The old module loads the QEMU guest
#    profile only when the flag is true. Here the aspect body loads it always, because a consumer
#    reaches the body only when it includes the aspect.
# 3. **`kdnConfig.inputs` becomes the aspect file's own `inputs` argument.** The target module below
#    closes over `inputs.nixpkgs`, so the target itself takes no custom argument. That is the
#    drop-in rule of ../README.md.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. This aspect declares no option at all.
# 3. **No custom module argument.** The target below is a plain attribute set.
{ inputs, ... }:
{
  kdn.hw-darwin-utm-guest.nixos = {
    imports = [ "${inputs.nixpkgs}/nixos/modules/profiles/qemu-guest.nix" ];

    boot.initrd.availableKernelModules = [
      "xhci_pci"
      "sr_mod"
    ];
  };
}
