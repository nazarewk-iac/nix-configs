---
type: Task
description: Remove the practical concurrency ceiling of the llama-swap setup — one slot per model, four aliases sharing one process, no admission gate — and decide between config knobs, an external resource watcher, and llama-swap hooks.
status: in-progress
authored_by: agent
timestamp: 2026-10-27T21:00:00+01:00
---

# llama-swap concurrency: the queue is the bottleneck

> **State 2026-10-28:** the config half is implemented; the sidecar's _collect_
> half lives in [../llm-metrics-persistence/](../llm-metrics-persistence/definition.md)
> and its _control_ half is still open.
>
> - `swap.coResidentTiers` exists, and brys names two GPU tiers. Eval renders
>   `with_co: (0.8b | 2b | tmax-2b) & (granite-3b | ministral-3b-* | gemma-e2b) & (frontier)`,
>   bounded at one model per tier.
> - Tiered models are subtracted from `with_surveyed`, so no model is in two sets.
> - Slots: frontier **2** (down from 4), tiny GPU tier **4**, everything else 1.
>   Rationale in the commit and in the per-model table of [sets.research.md](sets.research.md).
> - **Not measured yet.** The collector is what turns the hypothesis into a number.
> - Control sidecar untouched: the measured fact that an unload truncates an
>   in-flight stream silently means the guard is a prerequisite, not a nicety.

# llama-swap concurrency: the queue is the bottleneck

## Context

A fleet of sub-agents is supposed to work in parallel. On `brys` it mostly
cannot, and the reason is in the generated config, not in the clients.

Measured from the live config on 2026-10-27 (`/nix/store/vhssi9i…-config.yaml`):

| Fact                        | Value                                                                                |
| --------------------------- | ------------------------------------------------------------------------------------ |
| Models with `--parallel 4`  | exactly two: `deepseek-v4-flash` and `qwen3.8-flash-next`, both with `--kv-unified`  |
| Models with `--parallel 1`  | every other model, including all the fast ones                                       |
| Aliases sharing one process | `chat-dumb-fast`, `code-quick-fast`, `tiny-quick-fast`, `grunt` are all `qwen3.5-4b` |
| Admission control           | none. llama-swap counts models, not bytes                                            |

So five "parallel" calls to `chat-dumb-fast` are five calls to one process with
one slot. They queue. See
[../gaz-den-workstation/research.md](../gaz-den-workstation/research.md#6-the-model-fleet-real-concurrency-not-a-list-of-names).

Related, and not duplicated here:

- [../llm-unified-kv-parallelism/definition.md](../llm-unified-kv-parallelism/definition.md) —
  gives a router unified KV plus parallel slots, and measures the result. That is
  the _inside-one-model_ half.
- [../brys-grunt-colocation/llama-router-scheduler.research.md](../brys-grunt-colocation/llama-router-scheduler.research.md) —
  the survey that chose llama-swap and rejected the alternatives. It also records
  that llama-swap has **no admission gate**.

This task is the _across-models_ half: how to get real throughput out of one box
when the work is many small calls, and whether a watcher outside llama-swap can
help.

## Stated direction

The owner wants, as the outcome of this task:

1. **sensible parallelism enabled for every model**, not only the frontier, with
   the value chosen per model from measurement; and
2. **a sidecar service** that watches the fleet — on events where an event exists,
   and on a short poll (a few seconds) where one does not.

Two facts found after this task was written change the shape of both, and are
recorded in [research.md](research.md):

- **llama-swap already exposes per-model performance**, so the sidecar is not a
  log parser. `/api/metrics/activity` returns one record per request with
  `model`, `tokens.prompt_per_second`, `tokens.tokens_per_second` and
  `duration_ms`. The sidecar's jobs are _control_ and _durable history_, not
  parsing.
- **The matrix sets, not `--parallel`, are what serialise the surveyed tier.**
  `with_surveyed` groups every surveyed model into one set, so they evict each
  other. Three sequential test requests (`tiny-dumb-fast`, `chat-dumb-fast`,
  `granite-4.2-3b`) left exactly one model resident. Raising `--parallel` does
  nothing while the set forbids co-residence; the set expression must change
  first.

## Stated premise

The owner intends to drop the alternative boot specialisations and keep only
`llms-frontier`. That is one fewer divergent model set to reason about, and it
makes `llms-frontier.nix` the single source of truth for what is served. Check
that every model this task needs is in that entry before relying on it, and
record any that are lost with `llm-small`.

## The questions

1. **What is the real ceiling today?** For each tier, how many genuinely
   concurrent requests does the box serve, and what does a second request cost in
   latency? Measure, do not reason from the flag list.
2. **Which aliases are secretly the same process?** The four-way `qwen3.5-4b`
   alias group is one. Are there others that matter to the fleet?
3. **Does raising `--parallel` help a small model?** It divides KV cache per
   slot unless `--kv-unified` shares it. For a 16K-context 4B model on a GPU the
   KV is cheap; for a 30B on the CPU it is not. Measure one of each.
4. **Can a model be _loaded_ on demand without a client paying for it?** The
   first request to a cold alias pays a 30–120 s load, and under CPU pressure
   more. A preload step would remove that from the critical path.
5. **Is there a hook on model load?** This is the owner's explicit question. The
   honest answer today is in [research.md](research.md): llama-swap exposes
   `hooks.on_startup.preload` and nothing else event-driven, so a "run this when
   model X loads" hook does not exist in v249.
6. **Would an external watcher do better?** A small service that reads
   `/api/events`, `/running` and cgroup memory, and acts through
   `POST /api/models/unload/:id` or by starting a systemd unit. Decide whether
   this is worth its own moving part on a box that must stay up for the fleet.
7. **What is the smallest change that lifts the ceiling?** Prefer a config knob
   to a new daemon. A watcher is justified only if a knob cannot do the job.

## Proposals to evaluate, in order of cost

| Option                                                            | Cost                 | What it buys                                      |
| ----------------------------------------------------------------- | -------------------- | ------------------------------------------------- |
| Re-point the fleet at **distinct** aliases instead of one         | none, a docs change  | real parallelism across processes, no code        |
| Per-model `--parallel` + `--kv-unified` on the fast tier          | a config line        | concurrent requests inside one model              |
| Second process of the same GGUF on a second port                  | one more model entry | true parallelism when one process is the limit    |
| `hooks.on_startup.preload` for the aliases the harness uses       | a config key         | no cold-start stall at session start              |
| A tiny "preload this alias" call in the harness before delegating | a script step        | cold start moved off the critical path            |
| An external watcher with cgroup admission and unload control      | a new service        | OOM safety, RAM-aware eviction, preload on demand |
| A rack of small models pinned on the GPU                          | config + VRAM budget | many-cheap-workers behaviour, at 8 GB             |

## Deliverables

1. **A set-expression change** that lets the chosen groups co-reside, plus
   `--parallel` where the measurement justifies it. Both land in
   `modules/den/aspects/llm.nix` (`matrixSets` and the per-model `perf.parallel`).
2. **A sidecar service** (`systemd` unit, in the `llm` aspect's neighbourhood). Its
   two jobs:
   - **collect**: subscribe to `/api/events` (verified to carry `activity`,
     `modelStatus` and `inflight`) and append one line per finished request, so
     history survives a ring rollover and a restart. Subscription, not polling,
     because polling reads a bounded ring and loses records under a burst. The
     durable-storage half is [../llm-metrics-persistence/definition.md](../llm-metrics-persistence/definition.md).
   - **control**: keep the fleet inside the box. Subscribe to `/api/events` where
     it is useful, and act through the unload endpoint. It must never unload a
     model with a request in flight, and it must never act on a guess when it can
     read `/running` and `/api/metrics/stats`.
     It is a small Go/shell/Python service, and it must be small: the box also runs
     the models.
3. **A measured table**: alias, process, slots, observed concurrent requests,
   latency at 1 and at N, with the command that produced each number.
4. **Updated guidance** in `.agents/skills/kdn-llms/SKILL.md` and
   `docs/local-llms.md`: the alias-to-process map, the set groups, and the rule
   that fan-out must be across co-resident groups.

## Acceptance

- Two of the previously exclusive surveyed models are resident at the same time
  and both answer a request, with the numbers recorded.
- A second concurrent request to a model at `--parallel 2` measurably overlaps the
  first; the latency at N is recorded.
- The sidecar runs as a NixOS unit, has a test, and a restart of llama-swap leaves
  the collected history intact.
- An OOM is either prevented by the sidecar or explained by the absence of an
  admission gate, with the numbers.
- Nothing unloads a model mid-request. Prove it by trying: start a slow stream,
  call the unload endpoint through the sidecar instead of directly, and show the
  stream still finishes. (Called directly, llama-swap truncates the stream
  silently — see [control.research.md](control.research.md) — so the sidecar is
  the only thing standing between a watcher and a broken answer.)

## Risks

| Risk                                                           | Mitigation                                                                                                                                                                                                                                            |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Raising `--parallel` on a CPU model multiplies KV RAM and OOMs | measure KV per slot first; `--kv-unified` shares the pool                                                                                                                                                                                             |
| A watcher unloads a model mid-request                          | **llama-swap does not protect in-flight requests.** Measured: an unload during a stream truncates it silently — HTTP 200, no `[DONE]`, no error to the client ([control.research.md](control.research.md)). The watcher must enforce the rule itself. |
| Two processes of one GGUF fight over page cache                | measure; the 45 GB threshold in the colocation research applies                                                                                                                                                                                       |
| A preload hook delays startup past the health check            | preload asynchronously, never block the listener                                                                                                                                                                                                      |
