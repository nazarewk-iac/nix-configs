# The `development/documents` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It adds `marksman`, the Markdown language server, to Helix.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **One class only.** The old module holds a Home Manager half and a NixOS half, and the NixOS
#    half only forwards the `enable` to Home Manager. den needs no forward, so this aspect exports
#    the `homeManager` class alone.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `pkgs` only.
{ ... }:
{
  kdn.dev-documents.homeManager =
    { pkgs, ... }:
    {
      programs.helix.extraPackages = with pkgs; [ marksman ];
    };
}
