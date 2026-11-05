---
type: Task
description: Deploy LiteLLM as a NixOS container on etra as the single entrypoint for the local LLM fleet, fully declaratively (no DB, no Web UI), register brys as a backend, expose Prometheus metrics, and define how unreachable backends are handled.
status: open
authored_by: agent
timestamp: 2026-11-05T09:49:54+01:00
---

# LiteLLM gateway on etra

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
