---
type: Reference
description: How the per-service DNS subdomains under the NetBird peer domain were created (NetBird Cloud DNS Zones API), with the exact records and the API behaviours worth remembering.
timestamp: 2026-11-07T21:00:00+01:00
---

# NetBird DNS zones for per-service subdomains

## Why

NetBird MagicDNS resolves each peer as `<peer>.priv.nb.net.int.kdn.im`. It does
NOT resolve service subdomains such as `litellm.etra.priv.nb.net.int.kdn.im`.
To make those resolve, add **custom DNS Zones** that map the names to the peer
IPs. The Caddy vhosts then serve each service on its own subdomain.

## Account facts

- NetBird is the **Cloud** offering: the client `ManagementURL` is
  `https://api.netbird.io:443` (not self-hosted).
- API base `https://api.netbird.io`, auth header `Authorization: Token <token>`.
  The token is in `pass show netbird/kdn.im/access-token`.
- MagicDNS peer domain: `priv.nb.net.int.kdn.im`.
- The `All` group (id `cdk49iqt2r9s739s9h6g`, 16 peers) is the distribution
  group, so every peer resolves the zones.

## API behaviours to remember

- `PUT /api/peers/{id}` accepts only `name`, `ssh_enabled`,
  `login_expiration_enabled`, `inactivity_expiration_enabled`,
  `approval_required`, `ip`, `ipv6`. It **silently ignores** an
  `extra_dns_labels` field even though peers return one. So a peer cannot be
  given extra names through the public peer API.
- A DNS Zone whose `domain` equals the peer domain (`priv.nb.net.int.kdn.im`)
  is rejected: `422 zone domain … conflicts with peer dns domain`.
- A DNS Zone at a **subdomain** of the peer domain IS allowed (e.g.
  `etra.priv.nb.net.int.kdn.im`), and its records give the exact desired FQDNs
  (`litellm.etra.priv.nb.net.int.kdn.im`). Use one zone per host.
- Record name must be the full FQDN, within the zone's domain. `A` record to the
  peer's IPv4 overlay address (`100.79.x.y`); `ttl 300`.

## What was created

> Update: the explicit per-service `A` records below were later replaced by one
> **wildcard CNAME per host** (`*.etra…` → `etra.priv…`, etc.), so any service
> subdomain resolves without a new DNS entry. Internal-CA certificates stay
> **per-service** (each leaf lists its own SANs), so DNS is wildcard but TLS is
> explicit.

Originally, one zone per serving host, distributed to `All`:

| Zone domain (id)                                     | A records → IP                                                         |
| ---------------------------------------------------- | ---------------------------------------------------------------------- |
| `etra.priv.nb.net.int.kdn.im` (dbnncmqfadhs73chcqfg) | `litellm.etra…` → 100.79.187.16, `prometheus.etra…` → 100.79.187.16    |
| `brys.priv.nb.net.int.kdn.im` (dbnnco3l0ubs73863mc0) | `llama-swap.brys…` → 100.79.164.36, `prometheus.brys…` → 100.79.164.36 |
| `oams.priv.nb.net.int.kdn.im` (dbnnco2fadhs73chcu2g) | `llama-swap.oams…` → 100.79.80.79                                      |

Verified: every name resolves from a NetBird client via `getent ahosts`.

## Reproduce (API calls)

```bash
T=$(pass show netbird/kdn.im/access-token)
API=https://api.netbird.io
ALL=cdk49iqt2r9s739s9h6g
hdr=(-H "Authorization: Token $T" -H 'Content-Type: application/json')

# Create a per-host zone (record name must be inside the zone domain):
zid=$(curl -s -X POST "$API/api/dns/zones" "${hdr[@]}" \
  -d "{\"name\":\"etra services\",\"domain\":\"etra.priv.nb.net.int.kdn.im\",\"enabled\":true,\"enable_search_domain\":false,\"distribution_groups\":[\"$ALL\"]}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')

# Add one A record per service:
curl -s -X POST "$API/api/dns/zones/$zid/records" "${hdr[@]}" \
  -d '{"name":"litellm.etra.priv.nb.net.int.kdn.im","type":"A","content":"100.79.187.16","ttl":300}'
```

List everything: `curl -s "$API/api/dns/zones" "${hdr[@]}"`.

## Related

- The Caddy subdomain vhosts and the internal-CA leaf SANs live in the
  `web-exposure` aspect and each host's `kdn.certificates.certs`.
- Peer IPs come from the `data/net` / host configs; keep them in sync with the
  `A` records above if a peer's overlay address changes.
