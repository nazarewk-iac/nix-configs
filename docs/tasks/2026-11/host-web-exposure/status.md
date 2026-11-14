---
type: Status
description: The shared route renderer, the etra web-exposure aspect, and clients-over-HTTPS are live; the brys/oams llm-aspect fold and the /prometheus external-url are not.
task: definition.md
authored_by: agent
timestamp: 2026-11-14T05:09:42+01:00
---

## Done so far

- **Shared renderer** `lib/web.nix` — `mkIndexHtml` and `mkCaddyRoutes` (one `handle_path <p>/*`
  per route, then `handle { root; file_server }`).
- **`web-exposure` aspect** `modules/den/aspects/web-exposure.nix` — `kdn.web.exposure`
  (domain, certName, title, routes) emits a Caddy vhost with a leaf credential and opens `80`/`443`.
- **etra wired** `hosts/etra/default.nix` — `domain = etra.priv.nb.net.int.kdn.im`, the `zellij-web`
  leaf, routes `/litellm -> 127.0.0.1:4000` and `/prometheus -> 10.233.101.2:9090`. Caddy serves the
  internal CA only (`auto_https off`).
- **Clients over HTTPS** — `data/llm.nix`: the `litellm` endpoint is
  `https://litellm.etra.priv.nb.net.int.kdn.im/v1`; the `brys` / `oams` direct endpoints carry
  `localHost` + a loopback `baseUrl`, and `lib/llm.nix` filters a `localHost` endpoint down to its
  own host.

## Remaining

- **brys/oams `llm`-aspect fold (part 3)**: the `llm` aspect still serves llama-swap at the vhost
  root; it does not use `mkCaddyRoutes` / `handle_path /llama-swap` / `mkIndexHtml`, and oams does not
  set the `kdn.llm.local.domain` / `certs` the fold needs. Moving llama-swap under `/llama-swap`
  (plus the index page) on brys and oams is the open piece.
- **`/prometheus` sub-path (part 4)**: `prometheus-container.nix` has an `extraFlags` option, but no
  dedicated `externalUrl`, and `--web.external-url=https://<host>/prometheus/` is not yet passed for
  the etra route.

## Next directions

1. Add the `llm`-aspect fold so brys and oams serve llama-swap under `/llama-swap` with an index page,
   reusing `mkCaddyRoutes` / `mkIndexHtml`; set the slot `domain` / `certs` on oams.
2. Add an `externalUrl` option to `prometheus-container` and pass `--web.external-url` +
   `--web.route-prefix=/` for the etra `/prometheus` route so Prometheus emits prefix-correct links.
3. Activate brys and oams, then verify each host's index page and sub-paths.
