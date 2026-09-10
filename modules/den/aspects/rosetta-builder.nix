# The `rosetta-builder` slot, as a den aspect.
#
# `modules/slots/rosetta-builder/default.nix` stays in place and keeps working. This file is the
# parallel den implementation. The two share no code today, on purpose: a shared helper would tie
# the deprecated tree to the new one.
#
# This slot comes first because it is the smallest slot that targets `darwin`, and because
# checkpoint 002 wants exactly this module as a plain drop-in for an external adopter.
#
# ## Two deliberate limits
#
# 1. **The aspect takes no entity argument.** An aspect that reads `{ host, ... }` resolves to an
#    empty module across the export boundary, with no warning. That is condition 2 of the 004
#    spike. A consumer that needs host data sets a plain option instead.
# 2. **The aspect declares no `enable` option.** Inclusion is the switch: a den entity includes the
#    aspect, and an adopter imports the resolved module. A second declaration of
#    `kdn.darwin.rosetta-builder.enable` would also collide with the slot in one module set.
#
# The slot's guest-size options (`guest.diskSizeMax`, `guest.minFree`, `guest.maxFree`) are **not
# ported yet**. The slot keeps them, and every real host still goes through the slot.
{ inputs, ... }:
{
  den.aspects.rosetta-builder.darwin = {
    imports = [
      inputs.nix-rosetta-builder.darwinModules.default
    ];

    # The upstream default is already true. It stays explicit here.
    nix-rosetta-builder.enable = true;
    # Power the guest off when it is idle.
    nix-rosetta-builder.onDemand = true;
    # Let the guest pull build inputs from a public cache. Otherwise the host uploads every input
    # over the slow guest link — see docs/multi-arch-builder.md, "Sharing the store".
    nix.settings.builders-use-substitutes = true;
  };
}
