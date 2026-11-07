---
type: Task
description: Decide how far to lock down the containers and the web edge — whether to containerize llama-swap and Caddy, use unix sockets, and add per-service container networks — with the recommendation for each and the reason.
status: open
authored_by: agent
timestamp: 2026-11-07T21:54:36+01:00
---

# Container networking lockdown ideas

## Context

After moving the per-host web exposure to Caddy subdomains, the containers
(prometheus, litellm, build-farm) use the repo rule "private network + narrow
socat relay". This task records the options considered for tightening the
remaining services and the edge, what to adopt, what to skip, and why. The one
item already done is noted.

## Options and recommendations

| # | Option | Verdict | Effort | Why |
|---|--------|---------|--------|-----|
| 1 | **LiteLLM on a Caddy-only unix socket** | **DONE** | S | Removes the host TCP listener; only Caddy reaches the gateway. See below. |
| 2 | Containerize **llama-swap** | **Optional → adopt via OCI** | M–H | Upstream is container-native. The cost is GPU/RAM plumbing, not the idea. |
| 3 | Containerize **Caddy** | **Skip** | M | Edge isolation is real, but it needs host-loopback upstreams; host-net/relays cancel the gain. |
| 4 | **Multiple networks per container** (one per consumer) | **Skip** | M–H | Consumers are mostly the host; nspawn/NixOS model one veth; more firewall surface. |

## 1 — LiteLLM unix socket (done)

`hosts/etra/litellm.nix` now has two narrow ingresses instead of the
`0.0.0.0:4000` relay:

- `litellm-ingress-sock`: `socat UNIX-LISTEN:/run/kdn/litellm.sock`, runs as
  `caddy`, socket `0660 caddy:caddy`. Caddy proxies
  `unix//run/kdn/litellm.sock`. No other local user and nothing off-host can
  reach the gateway.
- `litellm-ingress-prom`: `TCP-LISTEN:4000,bind=10.233.101.1` only, so the
  Prometheus container still scrapes through the bridge.

Verified: socket owned `caddy:caddy`, no `0.0.0.0:4000`, subdomain works,
`up{job="litellm"}` = 1.

## 2 — Containerize llama-swap (follow-up)

- **For:** official container images; isolation; consistency with the other
  containerized services.
- **Must handle:** GPU devices (`/dev/dri`, `/dev/kfd`, Mesa ICDs,
  `MESA_VK_DEVICE_SELECT`), `LimitMEMLOCK`, hugepages/NUMA (host-kernel; never
  cap the cgroup memory or a large model OOMs), bind `modelsDir`/`sessionStore`,
  and loopback `39700` → relays for Caddy, Prometheus, the compat proxy and the
  NetBird relay.
- **Runtime matters:** the repo's containers are `systemd-nspawn`
  (`privateNetwork`); llama-swap's story is **OCI** (Docker/Podman `--device`).
  Cleanest is to add an OCI runtime; replicating it in nspawn is more friction
  for the same isolation.
- **Recommendation:** adopt **only** via OCI with device passthrough, no memory
  cap, published/host ports, as a separate tested change with a GPU + large-model
  soak test. Keep it on host if owning GPU-in-container debugging is unwanted.

## 3 — Containerize Caddy (skip)

- Real motivation: it is the mesh/WAN-facing TLS edge.
- Blocker: it must reach host-loopback upstreams (`39700` llama-swap, the
  gateway socket) and the Prometheus bridge. Under `privateNetwork`, `127.0.0.1`
  is the container's own loopback, so this becomes host-networking (no isolation)
  or many relays for the one 443 entrypoint. TLS key delivery moves from
  `LoadCredential` to a bind mount.
- **Recommendation:** skip; harden the host `caddy.service` unit instead
  (sandboxing directives, minimal `ReadWritePaths`).

## 4 — Multiple networks per container (skip)

- Idea: one veth/bridge per consumer, container listens on `0.0.0.0`, each
  consumer reaches it on its own network — no relays/port remaps.
- Reality: consumers here are mostly the host (Caddy, operator), so it
  re-expresses "single bridge + per-interface firewall". The NixOS `containers`
  module models one `hostAddress`/`localAddress`; multiple veths need
  `extraArgs`/manual networkd. Containers cannot see each other without a shared
  L2 bridge, so container→container still needs host routing or a common bridge.
- **Recommendation:** skip per-consumer veths. For clean container→container
  scrape, use **one shared monitoring bridge** that scrape targets attach to.

## Suggested order (if pursued)

1. llama-swap into OCI with GPU passthrough + soak test (largest, highest risk).
2. Hardening pass on the host `caddy` unit (cheap, no networking change).
3. Optional: unix-socket shims for Prometheus/llama-swap if non-root local-user
   isolation is wanted (they are TCP-only, so a `socat` shim each).
4. Only if real multi-tenant needs appear: a shared monitoring bridge.

## Related

- [docs/nixos-containers.md](../../../nixos-containers.md) — the private-network +
  socat pattern.
- [docs/netbird-dns-zones.md](../../../netbird-dns-zones.md) — the subdomain DNS.
