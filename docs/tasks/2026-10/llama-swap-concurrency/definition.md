---
type: Task
description: Remove the practical concurrency ceiling of the llama-swap setup — one slot per model, four aliases sharing one process, no admission gate — and decide between config knobs, an external resource watcher, and llama-swap hooks.
status: open
authored_by: agent
timestamp: 2026-10-27T21:00:00+01:00
---

# llama-swap concurrency: the queue is the bottleneck

## Context

A fleet of sub-agents is supposed to work in parallel. On `brys` it mostly
cannot, and the reason is in the generated config, not in the clients.

Measured from the live config on 2026-10-27 (`/nix/store/vhssi9i…-config.yaml`):

| Fact | Value |
|---|---|
| Models with `--parallel 4` | exactly two: `deepseek-v4-flash` and `qwen3.8-flash-next`, both with `--kv-unified` |
| Models with `--parallel 1` | every other model, including all the fast ones |
| Aliases sharing one process | `chat-dumb-fast`, `code-quick-fast`, `tiny-quick-fast`, `grunt` are all `qwen3.5-4b` |
| Admission control | none. llama-swap counts models, not bytes |

So five "parallel" calls to `chat-dumb-fast` are five calls to one process with
one slot. They queue. See
[../gaz-den-workstation/research.md](../gaz-den-workstation/research.md#6-the-model-fleet-real-concurrency-not-a-list-of-names).

Related, and not duplicated here:

- [../llm-unified-kv-parallelism/definition.md](../llm-unified-kv-parallelism/definition.md) —
  gives a router unified KV plus parallel slots, and measures the result. That is
  the *inside-one-model* half.
- [../brys-grunt-colocation/llama-router-scheduler.research.md](../brys-grunt-colocation/llama-router-scheduler.research.md) —
  the survey that chose llama-swap and rejected the alternatives. It also records
  that llama-swap has **no admission gate**.

This task is the *across-models* half: how to get real throughput out of one box
when the work is many small calls, and whether a watcher outside llama-swap can
help.

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
4. **Can a model be *loaded* on demand without a client paying for it?** The
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

| Option | Cost | What it buys |
|---|---|---|
| Re-point the fleet at **distinct** aliases instead of one | none, a docs change | real parallelism across processes, no code |
| Per-model `--parallel` + `--kv-unified` on the fast tier | a config line | concurrent requests inside one model |
| Second process of the same GGUF on a second port | one more model entry | true parallelism when one process is the limit |
| `hooks.on_startup.preload` for the aliases the harness uses | a config key | no cold-start stall at session start |
| A tiny "preload this alias" call in the harness before delegating | a script step | cold start moved off the critical path |
| An external watcher with cgroup admission and unload control | a new service | OOM safety, RAM-aware eviction, preload on demand |
| A rack of small models pinned on the GPU | config + VRAM budget | many-cheap-workers behaviour, at 8 GB |

## Acceptance

- A measured table: alias, process, slots, observed concurrent requests, latency
  at 1 and at N, with the command that produced each number.
- A decision: which of the options above are adopted, and which are rejected with
  a reason.
- The fleet guidance in `.agents/skills/kdn-llms/SKILL.md` matches the measured
  reality, including the alias-to-process map.
- If a watcher is adopted: it is a NixOS unit in `modules/den/aspects/llm.nix`'s
  neighbourhood, it has a test, and it cannot unload a model with a request in
  flight.
- If nothing is adopted: the task closes with the measurement and the reason,
  which is still an answer.

## Risks

| Risk | Mitigation |
|---|---|
| Raising `--parallel` on a CPU model multiplies KV RAM and OOMs | measure KV per slot first; `--kv-unified` shares the pool |
| A watcher unloads a model mid-request | llama-swap queues rather than interrupts; the watcher must only unload idle models |
| Two processes of one GGUF fight over page cache | measure; the 45 GB threshold in the colocation research applies |
| A preload hook delays startup past the health check | preload asynchronously, never block the listener |
