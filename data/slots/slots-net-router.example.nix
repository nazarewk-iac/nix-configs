# The shape of `data/slots/slots-net-router.nix`, with documentation values only.
#
# ## What the real file holds
#
# The `net-router` aspect family holds no personal value. Every address, prefix, MAC address,
# address pool, port and DNS zone comes from the consumer. A den host reads them from a sibling file
# named `slots-net-router.nix`, exactly as a host reads `slots-ssh-access.nix` today.
#
# This example file is tracked and safe to publish. **It names no real network.** Every value below
# comes from a documentation range:
#
# | Range | Reserved by |
# |---|---|
# | `192.0.2.0/24`, `198.51.100.0/24` | RFC 5737, IPv4 documentation |
# | `2001:db8::/32` | RFC 3849, IPv6 documentation |
# | `00:00:5e:00:53:00` to `:ff` | RFC 7042, MAC documentation |
# | `example.` | RFC 2606, DNS documentation |
#
# ## How a host reads the real file
#
# A path literal behind `builtins.pathExists`, so a tree with no such file still evaluates. A
# `builtins.readFile` of an absent path aborts the evaluation, and `builtins.tryEval` does not catch
# that abort.
#
#     imports = builtins.filter builtins.pathExists [ ../../data/slots/slots-net-router.nix ];
#
# ## How the host renders the templates
#
# The aspect writes no `sops.templates`. It publishes `kdn.networking.router.templates` instead, and
# the host maps that one attribute set into its own renderer. The keys match `sops-nix` exactly:
#
#     sops.templates = config.kdn.networking.router.templates;
#
# ## What to copy where
#
# 1. Copy this file to `data/slots/slots-net-router.nix`.
# 2. Replace every value with your own.
# 3. Run `git add data/slots/slots-net-router.nix`. An untracked file is invisible to the
#    evaluation.
{
  kdn.networking.router = {
    # The DNS suffix of every automatic net domain. It must end with a dot.
    dhcp-ddns.suffix = "example.";

    # The two files that hold this router's own public addresses. The DDNS update script reads
    # them. Both options are mandatory, so a host that runs `net-router-ddns` must name them.
    addr.public.ipv4.path = "/run/secrets/router-public-ipv4";
    addr.public.ipv6.path = "/run/secrets/router-public-ipv6";

    # The uplink. `interfaces` names the physical members of the bond.
    nets.wan = {
      type = "wan";
      interfaces = [ "enp1s0" ];
      wan.asDefaultDNS = true;
      wan.gateway = [ "192.0.2.1" ];
      address = [ "192.0.2.2/30" ];
      prefix.delegated = "2001:db8:1::/64";
    };

    # The trusted LAN. One address family per `addressing` entry.
    nets.lan = {
      type = "lan";
      interfaces = [ "enp2s0" ];
      lan.uplink = "wan";
      firewall.trusted = true;
      prefix.ula = "2001:db8:2::/64";

      addressing.v4 = {
        subnet-id = 1;
        network = "198.51.100.0";
        netmask = "24";
        pools.dynamic = {
          start = "198.51.100.100";
          end = "198.51.100.200";
        };
        # One entry per static lease. The entry named after this machine gives the router its own
        # address, so every `addressing` entry needs it.
        hosts.router.ip = "198.51.100.1";
        hosts.workstation = {
          ip = "198.51.100.10";
          ident.hw-address = "00:00:5e:00:53:01";
        };
      };
    };

    # A tagged VLAN on the same physical port.
    nets.guest = {
      type = "lan";
      netdev.kind = "vlan";
      vlan.id = 100;
      interfaces = [ "enp2s0" ];
      lan.uplink = "wan";

      addressing.v4 = {
        subnet-id = 2;
        network = "198.51.100.0";
        netmask = "26";
        pools.dynamic = {
          start = "198.51.100.10";
          end = "198.51.100.60";
        };
        hosts.router.ip = "198.51.100.1";
      };
    };

    # One forward rule per pair of interfaces the firewall must let through.
    forwardings = [
      {
        from = "lan";
        to = "guest";
      }
    ];

    # The authoritative zones. Each name must end with a dot.
    domains."home.example." = { };

    # The TSIG key that Kea uses to update Knot. The `secret` value is a placeholder that the
    # renderer resolves, so no plaintext key enters the Nix store.
    tsig.keyTpls."kea.router" = {
      algorithm = "hmac-sha256";
      secret = "<SOPS:PLACEHOLDER:PLACEHOLDER>";
    };

    # One upstream per private zone that a different resolver owns.
    kresd.upstreams = [
      {
        description = "the corporate resolver";
        type = "FORWARD";
        nameservers = [ "192.0.2.53" ];
        domains = [ "internal.example." ];
      }
    ];
  };
}
