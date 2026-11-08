---
type: Task
description: Add DB-less, model-scoped client API keys to the LiteLLM gateway (custom auth) and a Requesty backend, and establish whether Pi can discover Requesty models through LiteLLM.
status: in-progress
authored_by: agent
timestamp: 2026-11-07T22:46:17+01:00
---

# LiteLLM client API keys and Requesty backend

## Goal

Non-master clients get their own API keys, each scoped to an allow-list of model
groups, so a "local-only" key can never spend on paid providers. The master key
keeps full access to all models (local + Requesty).

## Implemented and verified (2026-11-07, deployed on etra)

- **DB-less custom auth** `hosts/etra/litellm_auth.py`
  (`general_settings.custom_auth: "auth.user_api_key_auth"` +
  `custom_auth_run_common_checks: true`). It reads a sops-mounted JSON map
  `token -> {name, models}` and returns `UserAPIKeyAuth(models=...)`. Because
  custom auth runs **before** LiteLLM's own master-key check, the hook also
  handles the master key explicitly (PROXY_ADMIN, all models).
- **Enforcement** `hosts/etra/litellm_enforce.py` (`enforce.scope`, a `pre_call`
  hook). LiteLLM does NOT enforce a custom-auth token's `models` list unless
  `litellm.enable_post_custom_auth_checks` is True — and that is a getattr-only
  global, not a config key. So the scope is enforced here instead: admin/`models
  is None` → all; otherwise the requested group must be in the list, else 403.
  Fails closed on unexpected errors.
- **Keys file** `hosts/etra/litellm-keys.sops.yaml` (sops; etra ssh-host key +
  recovery YubiKeys), decrypted to `/run/configs/litellm-keys/keys/clients`,
  mounted into the container. Note: the sops `files` aspect discovers keys by
  parsing the YAML structure and **skips the first top-level leaf**, so the file
  is wrapped as `keys: { clients: <json> }` with `keyPrefix = "keys"`.
- **Two keys created** (rotate/remove as needed):
  - `sk-506d…60cf` "pi-fast" → `["chat-fast"]`
  - `sk-b697…fd16` "pi-all-local" → the local aliases (no `requesty/*`)
- Container ordering fixed: `container@litellm` now starts after
  `sops-install-secrets` (the keys-file bind source must exist, or nspawn fails).

**Verified:** master → `chat-fast` 200, `chat-deep-slow` 200 (all); client
`pi-fast` → `chat-fast` 200, `chat-deep-slow` **403**, `requesty/...` **403**,
unknown key **401**. `/v1/models` (master) = 36 entries incl. 3 explicit
Requesty ids.

## Requesty backend — findings (important)

Decisions were driven by source inspection of LiteLLM 1.102.1 + live tests:

1. **No first-class Requesty provider**; it is OpenAI-compatible.
2. **`model_name: "requesty/*"` wildcard is misleading and broken.** It does not
   route (404 "model group not found"), and it fills `/v1/models` with ~229
   `requesty/<name>` entries that are LiteLLM's **OpenAI price-map names**, NOT
   Requesty's real catalog (Requesty currently exposes only 4 ids). **Do not use
   the wildcard.**
3. **Explicit deployments are the right shape** and list correctly
   (`requesty/deepinfra/deepseek-v4.1-flash-1017`, `…/runware/…`,
   `…/tensorx/qwen3.8-flash-next`).
4. **Calling still 404s — a relay cannot front a vhost-routed upstream.** The
   `socat OPENSSL` egress relay keeps the client's `Host` header = the relay
   address (`10.233.100.1:8445`), so Requesty serves its default vhost and 404s.
   A raw TLS tunnel cannot rewrite `Host`. **Fix:** give the container real
   internet **egress (NAT)** and set `api_base https://router.requesty.ai/v1`
   directly (no relay). Not done in this task — see Open items.

## Pi auto-discovery answer (the operator's doubt)

**No real auto-discovery.** Through the gateway, Pi's `--list-models` shows only
its static `models.json` catalog (56 entries, local aliases). The gateway's own
`/v1/models` can list model groups, but the wildcard's "hundreds of requesty
models" were fake price-map names, and the 3 explicit ones do not route yet. To
surface real Requesty models to any client you must **enumerate them explicitly**
(few, and Requesty's real set is small) — there is no catalog pass-through.

## Decisions

- DB-less over Postgres: `custom_auth` + `pre_call` enforcement (no DB, no
  prisma engine). DB remains optional later for real virtual keys/budgets.
- Scope by model-group name; "disallow paid" = omit `requesty/*` from a key.
- Master key handled inside the hook (must be), keeps full access.
- Explicit Requesty deployments, not wildcard.
- Requesty calling deferred until container egress (NAT) exists; the relay is a
  dead end.

## Caveats

- Key list lives in the hook file path; rotating keys = edit the sops file.
- `pre_call` enforcement matches the exact model-group string; an alias that
  maps to a group must be listed as that group name.
- The 3 Requesty deployments currently 404 on call and are health-checked every
  30 s (harmless 404s, log noise). Consider removing them until NAT egress lands.
- `custom_auth` means **all** non-master traffic goes through the hook; a bug in
  it can lock out clients — the hook fails safe (401 only for unknown keys,
  master always allowed) but review before exposing.

## Open items / next steps

1. **Requesty egress**: enable outbound NAT for the litellm container (or run it
   with an egress path that preserves the real Host) and switch `api_base` to
   `https://router.requesty.ai/v1`; then verify a master call 200 and a
   local-only key still 403.
2. Decide whether to auto-enumerate Requesty's `/v1/models` into `model_list` at
   deploy time (small, curated) since there is no runtime discovery for clients.
3. Consider DB mode later for budgets/rotation/UI, if ever needed.
4. Orchestrator/default policy (from the auto-router task): cheap tasks should
   default to `chat-fast`, using a scoped key rather than the master key.

## Update 2026-11-07 (later): discovery script, all-models key, egress plan

### All-models non-master key (staged, not yet deployed)
The keys file now also holds a key with NO `models` field (`{"name":"all-models"}`).
The auth hook returns `models=None` for it and the enforce hook treats `None` as
"all models", so this non-master key can call every group incl. `requesty/*`.
Takes effect on the next `switch` (the sops file is part of the system closure).

### Discovery script (done, tested)
`hosts/etra/litellm_requesty_discover.py` fetches Requesty's real `/v1/models`
and builds explicit LiteLLM deployments. Tested live against
`https://router.requesty.ai` — it returns the 4 real ids (the wildcard's fake
price-map names are gone by construction). Two modes:
- print: a JSON list of deployment dicts.
- `--base BASE.json --out OUT.json`: load a base config, replace any `requesty/…`
  deployments, write the merged config. `urllib` honours `HTTPS_PROXY`.

### Preferred integration: server-side, interaction-less (designed, not wired)
Because LiteLLM's `model_list` is static at start, discovery must run where the
config is produced. Two options:
1. **Build-time (Nix)**: commit a generated `requesty-models.json` and have
   `litellm.nix` read it. Deterministic, but needs a manual/CI refresh — not
   interaction-less.
2. **Runtime (preferred)**: the container's litellm unit becomes a wrapper:
   ```sh
   cp /etc/litellm-base/config.json /tmp/litellm-config.json   # Nix base, no requesty
   python3 /etc/litellm/litellm_requesty_discover.py \
       --base /tmp/litellm-config.json --out /tmp/litellm-config.json || true
   exec litellm --config /tmp/litellm-config.json --host 0.0.0.0 --port 4000
   ```
   Discovery failure falls back to the base config (gateway keeps serving local
   models). A container `systemd` timer re-runs discovery and restarts litellm
   periodically. This is the interaction-less path.
   The Nix-generated config stops listing requesty (base only); requesty groups
   appear at runtime. Consequence: only `models=None` keys (master + `all-models`)
   can reach the dynamic `requesty/*` names; scoped local keys stay local (fine).

### Egress requirement (blocker before Requesty works)
The container has no internet route; the `socat OPENSSL` relay keeps the relay's
Host header, so Requesty 404s. It must reach `https://router.requesty.ai/v1`
directly with correct Host. Two ways:
- **NAT (preferred, requested)**: `networking.nat = { enable = true;
  internalInterfaces = [ "ve-litellm" ]; externalInterface = "wan"; };`, add a
  router forwarding `{ from = "ve-litellm"; to = "wan"; }`, and give the guest a
  default route + DNS (`networking.defaultGateway = hostAddress;
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];`). Risk: etra is the border
  router (custom nftables/router); must be verified live (SSH up, relays still
  work, router masquerade intact) with a rollback store ready.
- **CONNECT proxy**: a host `tinyproxy`/`squid` on `10.233.100.1:PORT`; set
  `HTTPS_PROXY` in the container. Preserves SNI/Host, no router changes.

**Not deployed.** These touch the border router and the container's network
namespace; they are staged with the snippets above and need a supervised switch
to verify (the discovery wrapper is safe — it falls back to the base config).

### Decisions
- Discovery is server-side; the printed/merged JSON is the source of truth for
  requesty groups (no hand-maintained list).
- Prefer runtime merge + timer over build-time JSON, for interaction-less refresh.
- Keep `requesty/*` reachable only to `models=None` keys while groups are dynamic.
