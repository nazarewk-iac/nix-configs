# The openfortivpn client of the old `networking` area, as a den aspect. It ports
# `modules/universal/networking/openfortivpn/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It puts the `openfortivpn` command on the path. On NixOS it also writes one pppd option,
# `ipcp-accept-remote`. Without that option pppd rejects the peer address a FortiGate gateway sends,
# and the tunnel never comes up.
#
# ## Class list: `nixos`, `darwin` and `homeManager`
#
# The old module puts the package outside its context guard, so the command reaches a Darwin host and
# a Home Manager user too. Only the `nixos` target writes the pppd option, because `/etc/ppp` belongs
# to a Linux pppd.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The package goes through the native option per class.** ../common/filter-packages.nix drops a
#    package the platform cannot build, and it warns. `openfortivpn` is Linux and Darwin both, so the
#    filter normally keeps it.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module takes `lib` and `pkgs` only.
{ ... }:
let
  filtered =
    lib: pkgs: import ../common/filter-packages.nix { inherit lib; } (with pkgs; [ openfortivpn ]);
in
{
  kdn.net-openfortivpn.nixos =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filtered lib pkgs;
      # pppd rejects the peer address a FortiGate gateway sends until this option is present.
      environment.etc."ppp/options".text = "ipcp-accept-remote";
    };

  kdn.net-openfortivpn.darwin =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filtered lib pkgs;
    };

  kdn.net-openfortivpn.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = filtered lib pkgs;
    };
}
