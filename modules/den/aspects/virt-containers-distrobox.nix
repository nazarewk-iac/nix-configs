# distrobox, as a den aspect. It ports
# `modules/universal/virtualisation/containers/distrobox/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs `distrobox`, which runs a graphical or a command-line program inside a container and
# shares the home directory with it.
#
# ## One class only
#
# The old module runs on NixOS only, so this aspect serves the `nixos` class only.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` does not survive.** The target writes `environment.systemPackages`.
#    Design B.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `lib` and `pkgs` only.
{ ... }:
{
  kdn.virt-containers-distrobox.nixos =
    { lib, pkgs, ... }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      environment.systemPackages = filterPackages [ pkgs.distrobox ];
    };
}
