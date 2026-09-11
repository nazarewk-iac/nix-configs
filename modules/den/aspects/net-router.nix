# The `networking/router` module of the old tree, as a den aspect family.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns one machine into a home router. The old module holds five capabilities in one 1833-line
# file. This family gives each capability its own aspect, and `includes` joins them:
#
# | Aspect | It adds |
# |---|---|
# | `net-router` | the net graph, `systemd-networkd`, the firewall, NAT and the forward rules |
# | `net-router-dhcp` | Kea DHCPv4 and DHCPv6 |
# | `net-router-dns` | the `kresd` recursive resolver |
# | `net-router-ddns` | authoritative `knot`, the TSIG keys and the Kea-to-Knot DDNS bridge |
# | `net-router-dns-rewrites` | the CoreDNS suffix-rewrite bridge |
#
# The DAG is a diamond: `net-router-ddns` includes both `net-router-dhcp` and `net-router-dns`, and
# each of those includes `net-router`. den collapses a diamond to one import — see ../README.md.
#
# A consumer that wants the full old behaviour includes `net-router-ddns` and, when it holds
# rewrites, `net-router-dns-rewrites`.
#
# ## Why a family, not one file
#
# The old module gates nothing: `enable = true` starts networkd, Kea, kresd and knot together. An
# aspect has no `enable`, so a one-aspect port would start all four for every consumer. The seam is
# real: a DHCP-only router and a resolver-only router are both valid machines, and the CoreDNS
# bridge MUST be separate. `service-coredns` sets `services.coredns.enable = true` with no gate, so
# an unconditional include of it would start CoreDNS on a router that holds no rewrite. The old
# module gates that path on `cfg.kresd.rewrites != { }`, and `lib.mkIf false` cannot hide it.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch. The two per-entry `enable` options stay, because
#    `checks/standalone.nix` cannot reach an option inside an `attrsOf submodule`.
# 2. **The platform guard of the old module goes.** Each target names its own class instead.
# 3. **`sops.templates` goes.** Each aspect writes `kdn.networking.router.templates` instead, and a
#    consumer maps that one attribute set into its own secret renderer. The aspect needs no
#    `sops-nix`, so it evaluates in a bare NixOS consumer.
# 4. **`pkgs.jsonTemplate` goes.** ./net-router/json-template.nix holds the same two helpers, and
#    it renders with `builtins.toJSON` instead of a derivation. That drops two import-from-derivation
#    reads per Kea config.
# 5. **`pkgs.kdn.kdn-sops-secrets` goes.** `knot.ddns.secretsRenderer` names the renderer, and its
#    default is a pass-through shim.
# 6. **The three `kdn.fs.watch`, `kdn.managed` and `kdn.services.coredns` enables become
#    `includes`.** `kdn.env.packages` becomes `environment.systemPackages`.
# 7. **One host name leaves the source.** The old module writes one literal DDNS key id three
#    times. The port derives it from `kdn.hostName`.
# 8. **Two dead options go**: `dhcpv4.implementation` and `dhcpv6.implementation`. No line of the
#    old module reads either one.
#
# ## Where the personal values live
#
# The old module holds none. Every address, prefix, MAC, pool, port and zone comes from the
# consumer. A den consumer reads them from `data/slots/slots-net-router.nix`, and
# `data/slots/slots-net-router.example.nix` shows the shape with documentation values only.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
{
  kdn.net-router.includes = [
    kdn.fs-watch
    kdn.managed
    kdn.secrets
  ];
  kdn.net-router.nixos = import ./net-router/base.nix;

  kdn.net-router-dhcp.includes = [ kdn.net-router ];
  kdn.net-router-dhcp.nixos = import ./net-router/dhcp.nix;

  kdn.net-router-dns.includes = [ kdn.net-router ];
  kdn.net-router-dns.nixos = import ./net-router/dns.nix;

  kdn.net-router-ddns.includes = [
    kdn.net-router-dhcp
    kdn.net-router-dns
  ];
  kdn.net-router-ddns.nixos = import ./net-router/ddns.nix;

  kdn.net-router-dns-rewrites.includes = [
    kdn.net-router-dns
    kdn.service-coredns
  ];
  kdn.net-router-dns-rewrites.nixos = import ./net-router/rewrites.nix;
}
