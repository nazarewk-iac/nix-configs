# The `security/disk-encryption` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns the TPM 2.0 stack on, and it brings the disk-encryption command set with it. A host that
# unlocks a LUKS volume with a TPM needs both parts.
#
# ## The gap this file closes
#
# No other den file writes `security.tpm2.enable`. The `toolset` aspect ships `sbctl`, `tpm2-tools`
# and `tpm2-tss`, but a package alone starts no `tpm2-abrmd` resource manager and creates no
# `tss` group. So a den host had the tools and no TPM. Measured 2026-09-11.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The `kdn.toolset.fs.encryption.enable` write becomes an `includes` entry.** den collapses
#    the diamond, so `security-secure-boot` may name the same aspect and it loads once.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch, and this aspect declares no option at all.
# 3. **No custom module argument.** The target module below takes nothing but `...`.
{ kdn, ... }:
{
  kdn.security-disk-encryption.includes = [ kdn.toolset-fs-encryption ];

  # A real class key, not an `includes` list alone. `../lib.nix` derives the class list from the
  # aspect's own attribute names, and it treats `includes` as structural. So an aspect that holds
  # `includes` alone emits no pair and gets no check coverage, in silence.
  # A plain attribute set is enough here: the target reads no consumer option. Precedent:
  # ./toolset.nix:450.
  kdn.security-disk-encryption.nixos = {
    security.tpm2.enable = true;
  };
}
