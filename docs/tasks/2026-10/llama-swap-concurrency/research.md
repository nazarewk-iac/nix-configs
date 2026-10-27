---
type: Research
description: What the installed llama-swap can and cannot do about concurrency: the measured slot layout, the free-form settings channel, the real hook surface, and the control endpoints an external watcher would use.
task: definition.md
authored_by: agent
timestamp: 2026-10-27T21:05:00+01:00
---

# Research: llama-swap concurrency and hooks, as installed

Checked 2026-10-27 against the running binary on `brys` (`llama-swap-249`), the
generated config it is running, the packaged nixpkgs module, and the upstream
README and configuration docs for that tag.

## 1. The ceiling, measured from the running config

The live config is `/nix/store/vhssi9i…-config.yaml`. Per-model slot counts:

| Model | Slots | Notes |
|---|---|---|
| `qwen3.8-flash-next` | `--parallel 4` | `--kv-unified`, `--reasoning-effort low`, 1M ctx |
| `deepseek-v4-flash` | `--parallel 4` | `--kv-unified`, 320K ctx |
| every other model | `--parallel 1` | CPU or Vulkan0 |

Alias groups resolved from the same file (`aliases:` under each model):

```
qwen3.5-4b:   aliases: grunt, chat-dumb-fast, code-quick-fast, tiny-quick-fast
```

So four "different" fleet aliases are **one** `llama-server` with one slot. This
is the single biggest surprise for anyone designing a fan-out.

The frontier is parallel; the workers are not. A five-way fan-out to the cheap
tier is a five-deep queue.

## 2. The whole config surface is reachable from Nix

The nixpkgs module declares:

```nix
settings = lib.mkOption {
  type = lib.types.submodule { freeformType = settingsFormat.type; };
};
```

and `modules/den/aspects/llm.nix` passes `settings = swapConfig`. So **any**
llama-swap config key is reachable without touching nixpkgs — `hooks`, `macros`,
`ttl`, `filters`, `env`, `profiles`. The aspect's `swapConfig` currently renders
only `healthCheckTimeout`, `logLevel`, `logToStdout`, `logTimeFormat`,
`captureBuffer`, `includeAliasesInList`, `startPort`, `globalTTL`,
`unloadTimeout`, `routing.router` and `models`. Adding a key is a small change in
one function.

## 3. Hooks: what exists, what does not

| Want | Available in this version |
|---|---|
| Preload a set of models when llama-swap starts | **yes**, `hooks` — documented as "Preload models on startup with `hooks`" (upstream PR #235) |
| Run a command after a specific model finishes loading | **no** documented hook |
| Run something before a model is evicted | **no** documented hook |
| React to load/unload events from outside | **yes, indirectly**: an SSE stream (the README's nginx example proxies `/api/events`, which is the event stream the web UI uses) |

So the answer to "is there a hook we could use when loading new models" is: **not
for per-model events, but there is a startup-preload hook and an event stream
that an external process can subscribe to.** A sidecar is therefore a supported
pattern, not a hack.

## 3b. Verified control surface

From the project README, tag `v249`:

| Endpoint | Verified meaning |
|---|---|
| `GET /running` | models resident now |
| `POST /api/models/unload` | unload all running models |
| `POST /api/models/unload/:model_id` | unload one model |
| `/logs`, `/logs/stream`, plus `/proxy`, `/upstream` and `/{model}` variants | buffered and live logs, per stream or per model |
| `/metrics` | system and GPU metrics for Prometheus (no per-model t/s) |
| `/health` | liveness |
| `/ui` | web UI, including a model load/unload panel |
| `/upstream/:model_id` | direct access to one model's server |
| `GET/PUT /api/profiles[/active]` | switch model-id replacement profiles |

The README shows "manually load and unload models" as a UI feature and documents
the unload endpoints explicitly. **The load endpoint path is not enumerated in the
README**, so it must be confirmed against the binary (open `/ui` and inspect, or
`GET /api/models`) before a watcher depends on it.

## 4. What llama-swap does not do, and will not

- It has **no admission gate**. It counts models, not bytes. It will happily be
  asked for a model that does not fit, and the OOM kill is the failure mode.
  Confirmed earlier in
  [../brys-grunt-colocation/llama-router-scheduler.research.md](../brys-grunt-colocation/llama-router-scheduler.research.md)
  (the survey that chose llama-swap).
- It does not queue by priority across models. A request for a model in another
  matrix set evicts what is not in that set.
- It exposes no per-model throughput metric. `/metrics` is system-level only, so
  any queueing analysis has to come from the request side.

## 5. What parallelism costs, per tier

`--parallel N` without `--kv-unified` divides the context among N slots. With
`--kv-unified` the slots share one pool. The frontier already uses the shared
mode at 4 slots.

- A **GPU** model has the KV in VRAM. `qwen3.5-4b` at 16K ctx and one slot; two
  slots with unified KV roughly doubles concurrent capacity for little VRAM.
  Cheapest win on the box.
- A **CPU dense 27–30B** pays for every slot in RAM and in bandwidth. Raising
  `--parallel` there trades RAM for a concurrency that the memory bus cannot
  serve anyway.
- A CPU MoE (`lfm2.5-24b-a2b`, `nemotron`) is bandwidth-bound; extra slots mostly
  add queue depth, not throughput.

That ordering is the reason this task asks for a measurement per tier rather than
a blanket flag.

## 6. The related prior work

- [../llm-unified-kv-parallelism/definition.md](../llm-unified-kv-parallelism/definition.md) —
  config implemented, on-box measurement still pending. That task owns the
  "raise slots on the frontier" half.
- [../llm-unified-kv-parallelism/research.md](../llm-unified-kv-parallelism/research.md) —
  the `kv_unified` mechanism in llama.cpp source.
- [../llm-session-cache-persistence/](../llm-session-cache-persistence/definition.md),
  [../llm-prompt-cache-ram/](../llm-prompt-cache-ram/definition.md),
  [../llm-warm-start-session/](../llm-warm-start-session/definition.md) — the
  warm-start and cache-reuse levers. Not duplicated here.
- [docs/local-llms.md](../../../local-llms.md) — the serving document.

## 6b. Consequence for the fleet design

Until something here changes, the correct fan-out rule is: **one alias per
worker, distinct aliases.** Never many calls to one alias. That rule is already in
`.agents/skills/kdn-llms/SKILL.md`; this task is what would let us relax it.

## 6c. Note on the boot specialisations

The owner intends to keep only `llms-frontier`. That entry already sets
`withFrontier`, `withQwen`, `withGrunt`, `withSurveyed` and `withSwap`
(`hosts/brys/llms-frontier.nix:31-45`), so the whole surveyed fleet plus the GPU
grunt is served from it. The only set lost is `llm-small`'s `withSmall`, which
`withSurveyed` supersedes. Any model that exists **only** in the small set must be
re-homed or dropped deliberately.

## 6d. Not verified

- The exact load endpoint (`POST /api/models/load` is the likely shape, not in the
  README for the tag).
- Whether `hooks` in `v249` supports anything beyond startup preload. The docs
  page for hooks was not fetched; the README sentence is the only evidence used.
- Any real latency number for a second concurrent request. Nothing is measured
  yet; the task exists to produce it.
