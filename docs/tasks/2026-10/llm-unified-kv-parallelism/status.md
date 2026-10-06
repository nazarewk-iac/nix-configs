---
type: Status
description: Unified KV + parallel 4 and the llm-small spin-out are deployed and measured on brys; the client tiers needed a server-alias fix. Remaining: llm-small boot test and a few throughput rows.
task: definition.md
authored_by: agent
timestamp: 2026-10-06T12:50:00+02:00
---

# Status — deployed and measured on brys; client tiers fixed with server aliases

## Done so far

**Server slot and den aspect (`perf.kvUnified`).** Both `modules/slots/llm/default.nix`
and `modules/den/aspects/llm.nix` gained `perf.kvUnified` (`nullOr bool`, default
`null`). A non-null value emits `kv-unified = on` / `kv-unified = off`; `null`
emits nothing. This is the switch that decides whether an explicit `--parallel N`
divides or shares the context.

**DS4 concurrency (`hosts/brys/llm.nix`).** `deepseekPerf` sets `parallel = 4`
and `kvUnified = true`. No `--kv-unified-per-slot` cap anywhere.

**Small router spun out.** `hosts/brys/llm.nix` gained `withFrontier` / `withSmall`.
The shared appliance body moved to `hosts/brys/llm-appliance.nix`. Boot entries:
`llm-minimal` (DS4 only) and `llm-small` (`routers.small` only, new). Wired under
`specialisation.llm-minimal` / `specialisation.llm-small` in `hosts/brys/default.nix`.

**Client tiers (`hosts/oams/devenv.nix`).** The same DS4 at eight context sizes
(320K…16K) plus one opencode subagent per tier (`ds4-320k`…`ds4-16k`). `output`
scales with the tier (`min(8192, context/4)`). An 8K tier was tried and dropped:
opencode sends a ~5K-token system prompt plus tool schemas, so an 8K window
overflows and the request stalls. 16K is the smallest useful subagent tier —
verified 2026-10-06, a `ds4-16k` subagent read `hosts/brys/llm-routers.nix` and
returned the six model names.

**Deployed and measured (cold boot, 2026-10-06).** `nixos-rebuild.sh boot
remote=brys` + `select-boot-entry.sh brys llm-minimal --reboot`. Running
`nixos-system-brys-llm-minimal-26.11.20260908.d6524aa`, `isolcpus=1-15` and
`zfs_arc_max=8589934592` applied. Server log:
`n_slots = 4, n_ctx_slot = 327680, kv_unified = 'true'`. Only `llama-cpp.service`
runs (no small router).

| check | result |
|---|---|
| head-of-line blocking | a short request (8 tok) returned in **3.7 s** while a 256-token request was in flight (121.8 s) |
| DS4 residency | `RssFile` 92.6 GB, `RssAnon` 22.9 GB, `VmRSS` 115.5 GB |
| idle major faults (5 s) | **0** |
| OOM | none |
| DSpark at `parallel 4` | acceptance 0.44, mean len 2.32 (draft still works) |
| memory | 923 Mi free, 93 Gi buff/cache, 91 Gi available |

**The client tiers needed a server-side fix.** The research claimed an unknown
model id falls back to the frontier router. It does not: the compat-proxy routes
an unknown id to the frontier *upstream* but does not rewrite the id, and
llama-server rejects the unknown id with HTTP 400 (`model '...' not found`). A
tier is therefore routable only if the id is a real server alias. The
`deepseek-v4-flash-<n>k` ids are now aliases of `deepseek-v4-flash` in
`hosts/brys/llm.nix`. They add no KV cap and no memory. After a second cold boot
(gen 653) both `deepseek-v4-flash-8k` and `deepseek-v4-flash-128k` return HTTP
200 over `https://brys.priv.nb.net.int.kdn.im/v1`.

**Checks:** `standalone-slots`, `standalone-aspects`, `den-eval-coverage` pass.
`den-eval-llm` cannot run here (the den `gen-schema` input fails to fetch, HTTP
401, unrelated).

## Remaining

- Cold-boot `llm-small` once and confirm it serves the small set with DS4 absent
  (`nixos-rebuild.sh boot remote=brys` then `select-boot-entry.sh brys llm-small
  --reboot`).
- Aggregate-versus-serial throughput rows at `parallel 4` (the concurrency
  isolation is proven; the aggregate figure is not yet measured against a
  `parallel 1` baseline).

## Next directions

1. Re-enter the oams devenv shell so `opencode.jsonc` regenerates with the tier
   models and the `ds4-*` subagents.
2. Cold-boot `llm-small`, then close the task with a `done.md`.
