---
type: Task
description: Fork and integrate adeci/litellm-nix (Prisma 6, generated client, migrations, proxy extras, UI) to give the etra gateway an optional Postgres database — virtual keys, budgets, spend logs, and the admin UI — which the current DB-less packaged litellm cannot provide.
status: open
authored_by: agent
timestamp: 2026-11-08T17:01:26+01:00
---

# Postgres support for LiteLLM via a forked litellm-nix

## Context

The gateway (`hosts/etra/litellm.nix`) runs the **nixpkgs `litellm` package,
DB-less**: config is generated from `data/llm.nix`, auth is a `custom_auth` hook
with a sops key file, and model spans are enforced by a `pre_call` hook. That is
deliberate — the DB path was blocked because the packaged litellm pins
**python-prisma 0.15.0 (engine commit = prisma 5.17.0)** while nixpkgs ships
prisma-engines 6.x, and the package has **no generated Prisma client and no
`litellm_proxy_extras`**.

Consequences of DB-less (all confirmed from source earlier):
- No virtual keys/budgets/spend logs/teams, no admin UI — only the master key and
  our custom static keys.
- `/model/new` (runtime model add) needs a DB; discovered models need a restart.

## Proposal: fork + vendor `adeci/litellm-nix`

[adeci/litellm-nix](https://github.com/adeci/litellm-nix) (MIT) is **integration
work, not a LiteLLM fork**. From its README it:

- builds LiteLLM **with proxy extras, Prisma 6, a generated Prisma client,
  migrations, and UI assets**, then runs it as a NixOS service;
- exposes `packages.<system>.litellm-nix`, `nixosModules.default`, and a
  `checks.x86_64-linux.litellm-vm` VM test that validates the pinned
  litellm+prisma combination;
- runs as **`services.litellm-nix`** with mutable state in `/var/lib/litellm`,
  migrations in `litellm-migrations.service`, main service with schema updates
  disabled, UI assets copied to `stateDir/ui`;
- config: `enable`, `configFile`, `envFiles`, `databaseEnvFile` (must hold
  `DATABASE_URL` + `LITELLM_DATABASE_PASSWORD`), and `manageLocalPostgresql`
  (default true — orders after PostgreSQL, applies the password to the local
  `litellm` role);
- pins **its own nixpkgs** on purpose: the litellm and prisma-engines versions
  are validated together. Adopting it means running **its** litellm version, not
  nixpkgs'.

This is exactly the missing piece (Prisma 6 + generated client + migrations +
extras), so the DB blocker disappears.

### Why fork (vs. using the flake input directly)

Follow [forking rules](../../../.agents/rules/forking.md) and
[docs/guides/git-forking.md](../../../docs/guides/git-forking.md):

- Vendor into `nazarewk-iac/litellm-nix`, one jj bookmark per patch joined into
  `main`, pinned **rev + hash** in our flake inputs (never `main`/branch).
- Keeps the repo's own patches (see its `nix/patches/`) reviewable and lets us
  carry our own if the upstream module lacks an option we need (e.g. container
  placement, secret wiring, or a `stateDir` on ZFS).
- Using the upstream flake input unpinned would violate the vendoring rule and
  tie us to its cadence silently.

## Integration shape (decisions to make in this task)

The current gateway is a **systemd-nspawn container** with `privateNetwork`, a
socat ingress (now a Caddy-only unix socket), Prometheus bridge relay, a CONNECT
egress proxy for Requesty, and sops-mounted keys. `litellm-nix` is a **NixOS
service** module meant to run on the host. Two paths:

1. **Run `services.litellm-nix` on the host (recommended).**
   - Drops the container. The service is then on etra's host network: it can
     reach `router.requesty.ai` **directly**, so the whole CONNECT proxy
     (`litellm-requesty-proxy`, `HTTPS_PROXY`, the socat relays) becomes
     unnecessary — a real simplification.
   - Keep Caddy's `litellm.etra…` subdomain, but point it at the host service
     (loopback or the unix socket, whichever the module supports) instead of the
     container bridge.
   - Postgres: `services.postgresql` on etra with `ensureDatabases=["litellm"]`
     and a `litellm` role; `manageLocalPostgresql = true`.
   - Re-do the firewall/ingress: only Caddy (443) and loopback; no container veth.
2. **Use the module inside the container** (keep isolation).
   - More work: the container needs Postgres (in-container or a relay to the
     host), the migration service, and the module's `/var/lib/litellm` state on a
     bind mount. Only worth it if container isolation of the proxy is a hard
     requirement.

Recommendation: **path 1**, and take the simplification (no proxy/relays) — the
risk removed (internet egress) is exactly what the CONNECT proxy was working
around.

### Config, keys, secrets

- **configFile**: keep the generated `model_list` from `data/llm.nix` (aliases +
  un-aliased served base ids + curated `max_input_tokens`/`max_output_tokens` +
  the `chat-fast` pool + explicit Requesty deployments) — feed it as
  `configFile`. The fastest-fit / probe / enforce plugin `.py` files still load
  from beside the config (mount them into `stateDir` or point the module at them).
- **Secrets**: `databaseEnvFile` from sops (`DATABASE_URL`,
  `LITELLM_DATABASE_PASSWORD`); `envFiles` from sops (`LITELLM_MASTER_KEY`,
  `LITELLM_SALT_KEY`, `REQUESTY_API_KEY`). Postgres password also needs to reach
  `services.postgresql` for the role (`ensureUsers`/`ensureDBOwnership`, or
  `ensureDatabases` + a `sops` password applied via `manageLocalPostgresql`).
- **Keys migration**: replace the `custom_auth` + `enforce.py` model-scoping with
  **DB virtual keys** — `POST /key/generate` with `models=[…]` per client
  (`pi-fast`, `all-models`, …), master key stays admin. This is the actual payoff:
  budgets, spend logs, rotation, and the UI. Keep the existing local-scoped /
  all-models semantics by mapping each old key to a virtual key with the same
  `models` list. The `fastest` plugin and health routing are unaffected.
- **UI**: `stateDir/ui` served by the service; expose it (if at all) only under
  the Caddy subdomain behind the internal CA, never directly.

## Open questions

- Keep the container (path 2) or move to a host service (path 1)? (Recommend 1.)
- Postgres placement/backup: same ZFS state bucket as the gateway; `pg_dump`
  timer; retention for spend logs.
- Version policy: litellm-nix's pinned litellm may differ from our current
  1.102.1 — verify the generated config and plugins still load against it.
- Do the stateful pieces (Prisma migrations, UI state) belong in the repo's
  `sys/state` bucket on etra? (See [docs/nixos-containers.md](../../../nixos-containers.md)
  for the state/cache split if we stay containerised.)

## Acceptance criteria

- `nix build` of the forked `litellm-nix` + its `litellm-vm` check pass in our
  flake (vendored rev+hash).
- `services.litellm-nix` serves our generated config; `/v1/models` unchanged;
  local + Requesty calls 200; master works.
- A DB virtual key scoped to `chat-fast` gets 200 there and 403 elsewhere; an
  all-models key reaches Requesty; spend logs recorded; migrations applied on
  first boot and idempotent.
- No direct internet exposure: only Caddy 443 (internal CA) and loopback; if we
  keep the container, the CONNECT proxy still fronts SaaS egress.

## References

- <https://github.com/adeci/litellm-nix> (README facts above, fetched 2026-11-08).
- Current DB-less design + the prisma blocker: [../litellm-gateway/definition.md](../litellm-gateway/definition.md),
  [../litellm-client-keys-and-requesty/definition.md](../litellm-client-keys-and-requesty/definition.md).
- Fork/vendor rules: [.agents/rules/forking.md](../../../.agents/rules/forking.md).
