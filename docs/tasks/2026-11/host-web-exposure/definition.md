---
type: Task
description: Put a per-host Caddy reverse proxy on the default HTTPS port, fronting each host's HTTP services (litellm, llama-swap, prometheus) under path prefixes with an index page, and route all LLM client traffic through the HTTPS gateway except on the host that serves it.
status: in-progress
authored_by: agent
timestamp: 2026-11-07T14:20:00+01:00
---

# Per-host HTTPS exposure and gateway-only clients

## Context

LLM clients today use several transports: `brys` over HTTPS at its Caddy vhost
root, `oams` over plain HTTP on the LAN, and `litellm` over plain HTTP on the
NetBird address. That is inconsistent and leaks plain-HTTP where TLS is easy.

Goal: every host runs one Caddy reverse proxy on `:443`, authenticated with an
internal-CA leaf, and serves its own services under path prefixes with an index
page at `/`. LLM clients use the LiteLLM gateway over HTTPS everywhere; the two
serving hosts keep a direct loopback path so they still work offline.

## Proposed approach

### 1. A shared route renderer

`lib/web.nix` exports two pure helpers:

- `mkIndexHtml { title, links }` — the index page body for a host.
- `mkCaddyRoutes { indexTitle, routes }` — a Caddyfile fragment: one
  `handle_path <p>/* { reverse_proxy <up> }` per route (`handle_path` strips the
  prefix, so an API backend is unaware of the sub-path), then a final
  `handle { root * <index>; file_server }`.

Both the new aspect and the `llm` aspect call these, so there is one renderer.

### 2. New `web-exposure` aspect (for hosts with no existing vhost — etra)

Option `kdn.web.exposure = { enable, domain, certName, title, routes }`, where
`routes` maps a path prefix to `{ upstream, strip ? true }`. It emits
`services.caddy.virtualHosts.<domain>` with `tls <certPath> /run/credentials/...`
(leaf from `kdn.certificates.certs.<certName>` via `LoadCredential`), the routes
from `mkCaddyRoutes`, opens `80`/`443`, and sets `serverAliases` from the
certificate SANs.

etra wiring (`hosts/etra/`):

- `domain = "etra.priv.nb.net.int.kdn.im"`, `certName = "zellij-web"` (reuse the
  existing etra leaf).
- routes: `/litellm → 127.0.0.1:4000` (gateway ingress), `/prometheus →
10.233.101.2:9090` (prometheus-container guest).

### 3. Fold the `llm` aspect vhost into the same shape (brys + oams)

The `llm` aspect already builds a vhost when `domain`/`certs` are set. Change its
`extraConfig` to:

- `handle_path /llama-swap/* { reverse_proxy 127.0.0.1:<compatProxy.port> }`
- one `handle_path` per `kdn.llm.local.web.extraRoutes` (e.g. `/prometheus`)
- `handle { root; file_server }` with `mkIndexHtml`.

Then the root stops serving llama-swap at `/`; llama-swap moves to `/llama-swap`.
Activate it on oams by setting the slot `domain`/`certs` (oams has the
`zellij-web` leaf). brys already has the vhost.

### 4. Prometheus sub-path correctness

`handle_path` strips `/prometheus`, so Prometheus must emit absolute links under
the prefix. Add an `externalUrl`/`extraFlags` option to the `prometheus-container`
aspect and pass `--web.external-url=https://<host>/prometheus/` with
`--web.route-prefix=/`.

### 5. Clients: gateway over HTTPS, direct only on-host

- `data/llm.nix` `litellm.baseUrl = "https://etra.priv.nb.net.int.kdn.im/litellm/v1"`.
- Mark `brys` and `oams` endpoints `localHost = "brys"` / `"oams"` and give them
  a loopback `baseUrl` (`http://127.0.0.1:39700/v1`). `mkPiModelsJson` includes a
  `localHost` endpoint only when the consumer host matches; the opencode
  upstreams are declared per host (`hosts/*/devenv.nix`) so they follow.
- Result: a client on brys sees `brys` + `litellm` + `requesty`; on oams sees
  `oams` + `litellm` + `requesty`; everywhere else only `litellm` + `requesty`.

## Risks / notes

- Moving llamaswap off `/` breaks any client still on `https://brys…/v1`; the
  gateway move covers clients, and on-host clients use loopback.
- etra opening `443` globally (matching the existing llm gate) vs. only on
  `nb-priv` — start global, tighten later.
- Reusing the `zellij-web` leaf for the Caddy vhost is acceptable (same CN/SAN).

## Out of scope

- Public internet exposure and SSO — separate far-future task
  [`../moss-ingress-and-sso/definition.md`](../moss-ingress-and-sso/definition.md).
