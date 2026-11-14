---
type: Task
description: Deploy LiteLLM as a NixOS container on etra as the single entrypoint for the local LLM fleet, fully declaratively (no DB, no Web UI), register brys as a backend, expose Prometheus metrics, and define how unreachable backends are handled.
status: done
authored_by: agent
timestamp: 2026-11-05T09:49:54+01:00
---

# LiteLLM gateway on etra

> **Done.** See [done.md](done.md) for the solution and follow-ups.

## Context

Today every client talks to a specific host's llama-swap router. There is no
single entrypoint, no failover, and no cross-host view. `etra` is the LAN/WAN
router and already hosts the build-farm HAProxy container, so it is the natural
place for a gateway that must be reachable from everywhere.

LiteLLM provides an OpenAI-compatible proxy with routing, retries, cooldowns,
fallbacks, and Prometheus metrics. The goal is to run it **as code**: a config
file in the repo, no Postgres, no Web UI clicks, no `sk-` keys generated at
runtime.

## Key research findings

Full detail in [research.md](research.md). The decision-relevant points:

- **A database-free deployment is fully supported and is the right choice.**
  With `DATABASE_URL` unset, LiteLLM skips the Prisma client entirely and runs
  from `config.yaml`. You give up per-client virtual keys, budgets, spend logs,
  and the Admin UI — none of which we want. Auth becomes a single shared
  `LITELLM_MASTER_KEY`.
- **The master key is mandatory** in current versions; the proxy refuses to start
  with it unset or set to a known default. Supply it via `os.environ/` +
  systemd `EnvironmentFile` from sops.
- **Custom OpenAI-compatible backends** use `model: openai/<name>` +
  `api_base: http://<host>:<port>/v1` (the `/v1` is required).
- **The default timeout is 6000 s.** This must be clamped explicitly or a
  dead backend hangs a request for over an hour.
- **When all deployments for a model are down/cooling, LiteLLM returns HTTP
  429** (not 503) with a `retry-after` header on the inference path; 503 appears
  only on the `/health` endpoint.
- **Prometheus is behind a flag** (`litellm_settings.callbacks: [prometheus]`),
  and exposes **`litellm_deployment_state`** (0 healthy / 1 partial / 2 complete
  outage) — the metric to alert on.
- **No native wake-on-request / scale-to-zero exists.** Hooks and alerting
  primitives exist if we ever want to power on brys on demand; that is a
  separate research question, recorded in the task's research doc.

## Proposed approach

1. **Persistence first.** A `kdn.disks.persist` bucket entry for the container
   root and LiteLLM's runtime dirs, created and verified before activation.
2. **Container** in `hosts/etra/default.nix` following [docs/nixos-containers.md](../../../nixos-containers.md):
   `privateNetwork`, host/guest addresses, socat ingress on one port, both
   firewalls, `lib.mkIf`, ordering on `systemd.services."container@litellm"`.
3. **Config as code**: `hosts/etra/litellm.config.yaml` (or a data file) with
   `model_list` (brys first, oams when ready), `router_settings` with a sane
   timeout / retries / cooldowns / fallbacks, `litellm_settings.callbacks:
   [prometheus]`, and `general_settings.master_key: os.environ/LITELLM_MASTER_KEY`.
4. **Secrets** via `kdn.security.secrets.sops.files."litellm"` and a read-only
   bind mount into the guest.
5. **Prometheus**: either a small scrape config added to the existing brys-side
   Prometheus, or a minimal Prometheus beside etra. Decide during the work.
6. **Register brys**, then oams once its llama-swap exists.

## Acceptance

- `curl etra/v1/models` returns the union of backends; a chat completion through
  the gateway reaches brys.
- The config is entirely in the repo; recreating the container from scratch
  restores identical behaviour.
- No database process runs.
- `/metrics` exposes `litellm_deployment_state`, and a stopped brys flips it to
  2 within one health-check interval.
- A request to a model whose only backend is down returns a fast error (429 or
  5xx), not a 100-minute hang.

## Open questions

- Which host runs the Prometheus that scrapes the gateway? (brys has one; etra
  could host a proper one.)
- Do we want cheap virtual keys later? If so, a DB becomes necessary and this
  task's no-DB premise changes.
- Wake-on-request for brys is researched but out of scope here; see research.md.

## Progress 2026-11-05

- **Config as code**: `hosts/etra/litellm.config.yaml` — every brys alias from
  `data/llm.nix`, no DB, clamped router timeouts, prometheus callback.
- **Container**: `hosts/etra/litellm.nix` — private veth, narrow socat ingress
  (`:4000`) and egress (`:8443` -> brys compat proxy), persistence under
  `sys/state` + `sys/cache`, master key generated on first start.
- **Builds**: etra builds cleanly with the container included.
- **`autoStart = false`**: deliberately INERT.

### Blocker for activation

etra reaches brys (ping OK) but brys **drops etra** on both `39701` (compat proxy)
and `443` (Caddy). Opening that needs a firewall change on brys, which was not
done unattended. Steps to activate are in `hosts/etra/litellm.nix`:
1. On brys, allow etra -> brys:39701.
2. Set `autoStart = true`, rebuild etra.
3. Clients use `http://<etra>:4000/v1` with the master key.

### Not done
- Prometheus scrape of the gateway (brys has a Prometheus; etra does not yet).
- Registering oams as a second backend (blocked on the same firewall question
  plus oams being a laptop with the serving toggle).
- Wake-on-request: research only (see wake-on-request.research.md).

## ACTIVATED 2026-11-05

Live on etra (`autoStart = true`). Path: client -> etra:4000 -> LiteLLM
container -> host egress relay (10.233.100.1:8443) -> brys over NetBird
(100.79.164.36:39704) -> llama-swap. Verified with a real chat completion.

What it took beyond the initial code:
- brys' llama-swap needs an API key: etra joined the `llms` sops recipients (its
  SSH host key) and mounts `/run/configs/llms`, passing the real key to LiteLLM.
- the host firewall had to allow the egress port on `ve-litellm`, or the guest's
  backend calls were blackholed (60 s timeouts).
- brys needed a mesh relay: `39704` -> loopback llama-swap, firewall-opened only
  on `nb-priv`.

### Still open
- oams is not a backend (add once its serving toggle is proven).
- Reachability from non-NetBird LAN peers: the ingress binds 0.0.0.0 but etra's
  firewall trusts only `nb-priv`; open 4000 on the LAN interface for plain clients.
- Prometheus scrape of `/metrics` on the gateway.

## Progress 2026-11-07

- **#1 health checks + routing**: `background_health_checks`, `enable_health_check_routing`,
  interval 30s, staleness 120s. A blackholed backend is filtered before any connect
  (see routing-and-timeouts.design.md).
- **#2 Prometheus**: new `prometheus-container` den aspect; etra scrapes LiteLLM
  `/metrics` (unauth, `/metrics/`); verified target up, `litellm_deployment_state`
  ingested. The gateway's `/metrics` is exposed without auth.
- **#3 routing**: documented (weights per alias, pin-per-host via extra model_names,
  least-busy, latency-based, no warm-model preference without a plugin).
- **#4 clients**: gateway added to Pi (`data/llm.nix` litellm endpoint + all aliases)
  and to OpenCode (oams upstream). Client master key must be provisioned at
  `/run/configs/litellm/master-key`.
- **#5 config-as-code**: `hosts/etra/litellm.config.yaml` removed; the config is now
  generated in `litellm.nix` via `pkgs.formats.json` from `data/llm.nix` (36
  deployments, health/timeout settings), no flat file to sync.
- **#6 timeouts**: `request_timeout`/`timeout` 3600, `stream_timeout` 1800 (per-chunk,
  not total). A slow-but-alive 30-min-TTFT stream is not cut off; see design doc for
  the `0`/`null` caveats and the client `timeout=None` requirement.
