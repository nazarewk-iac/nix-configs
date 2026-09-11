# Vagrant, as a den aspect. It ports
# `modules/universal/virtualisation/vagrant/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs `vagrant`, which builds and runs a virtual machine from a `Vagrantfile`.
#
# ## It includes the libvirt aspect
#
# The old module writes `kdn.virtualisation.libvirtd.enable`. An aspect must not write another
# aspect's option, so this aspect **includes** `virt-libvirtd` instead. Vagrant needs a hypervisor,
# and libvirt is the one this tree provides. den collapses the diamond when the consumer includes
# both.
#
# ## One class only
#
# The old module runs on NixOS only, so this aspect serves the `nixos` class only. The included
# aspect still serves both of its own classes.
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
{ kdn, ... }:
{
  kdn.virt-vagrant.includes = [ kdn.virt-libvirtd ];

  kdn.virt-vagrant.nixos =
    { lib, pkgs, ... }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      environment.systemPackages = filterPackages [ pkgs.vagrant ];
    };
}
