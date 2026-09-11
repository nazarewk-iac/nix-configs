# The Caddy web server, as a den aspect. It ports `modules/universal/services/caddy/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs Caddy on a NixOS host, opens the two HTTP ports, and grants the service the one capability
# it needs to bind a privileged port. It states no site and no domain: a consumer writes
# `services.caddy.virtualHosts` itself.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` does not survive.** The target names its class, so it writes
#    `environment.systemPackages` directly. Design B.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only.
{ ... }:
{
  kdn.service-caddy.nixos =
    { config, lib, ... }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      services.caddy.enable = true;

      environment.systemPackages = filterPackages [ config.services.caddy.package ];

      networking.firewall.allowedTCPPorts = [
        80
        443
      ];

      systemd.services.caddy.serviceConfig.AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
    };
}
