# A fictional host graph for the `ssh-access` aspect. It names nothing real.
#
# The aspect holds no graph. A graph names hosts, LAN and WAN addresses, ports and private DNS
# zones, so it is the consumer's own private configuration. This file is the **test** consumer, so
# every value here is fictional:
#
#   * every name sits under `example.invalid`, the reserved name that never resolves (RFC 6761);
#   * every address comes from a documentation range — `192.0.2.0/24` and `203.0.113.0/24` (RFC
#     5737), and `2001:db8::/32` (RFC 3849);
#   * the identity file names a path that no machine holds.
#
# The creator's own graph stays in a git-ignored host file and never reaches this tree.
#
# The graph exercises all three edge kinds, so the emitted drop-in and the route logic both get a
# real test:
#
# | host | edge | kind |
# |---|---|---|
# | `alpha` | `from = "lan"` | direct, on that LAN |
# | `alpha` | `from = "internet"` | entry from anywhere, through an uplink |
# | `beta` | `from = "alpha"` | a relay hop through `alpha` |
{
  kdn.ssh-access.defaults.user = "den-mvp";

  # A machine-local key path. The aspect bakes none, because a key path names one machine's own
  # hardware key. This value is fictional and no file exists at it.
  kdn.ssh-access.defaults.identityFile = "~/.ssh/id_ed25519_den_mvp";

  # Extra Host patterns that also take the agent. A direct LAN name reaches the same key.
  kdn.ssh-access.identityAgentPatterns = [ "*.lan.example.invalid" ];

  kdn.ssh-access.uplinks.example-uplink.ipv4 = "203.0.113.10";
  kdn.ssh-access.uplinks.example-uplink.ipv6 = "2001:db8::10";

  # `alpha` is the entry host. It answers on its LAN, and it answers from anywhere through the
  # uplink's WAN address on a high port.
  kdn.ssh-access.hosts.alpha.hostKeyAlias = "alpha.example.invalid";
  kdn.ssh-access.hosts.alpha.reachedFrom = [
    {
      from = "lan";
      address = "alpha.lan.example.invalid";
      priority = 10;
    }
    {
      from = "internet";
      uplink = "example-uplink";
      port = 2222;
      priority = 80;
    }
  ];

  # `beta` answers on the LAN that `alpha` reaches, so every route to it relays through `alpha`.
  kdn.ssh-access.hosts.beta.user = "den-mvp-beta";
  kdn.ssh-access.hosts.beta.reachedFrom = [
    {
      from = "alpha";
      address = "192.0.2.20";
      priority = 30;
    }
  ];
}
