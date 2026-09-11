# The `development/llm/pi` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It registers the Pi coding agent as an application entry, so the `apps` aspect installs it and
# keeps its data directory across a wipe.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **One class only.** The old module holds a Home Manager half and a forward half. den needs no
#    forward: a consumer names the class it wants.
# 3. **The `apps` aspect comes in through `includes`.** It declares `kdn.apps`, and den collapses a
#    diamond, so several aspects may name it.
#
# The `enable` inside `kdn.apps.<name>` is an option of the `apps` submodule, not an option of this
# aspect. A submodule `enable` is allowed.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `pkgs` only.
{ kdn, ... }:
{
  kdn.dev-llm-pi.includes = [ kdn.apps ];

  kdn.dev-llm-pi.homeManager =
    { pkgs, ... }:
    {
      kdn.apps.pi.enable = true;
      # nixpkgs names the package `pi-coding-agent`. The binary is `pi`.
      kdn.apps.pi.package.original = pkgs.pi-coding-agent;
      # Pi keeps its configuration and its sessions in `~/.pi`. It has no XDG support yet.
      kdn.apps.pi.dirs.data = [ "/.pi" ];
    };
}
