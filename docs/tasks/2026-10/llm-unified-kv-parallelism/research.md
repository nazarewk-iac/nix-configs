---
type: Research
description: Theoretical exploration of 320K ctx with --parallel 4 under unified KV, and how to allow smaller-context sub-agents (client vs server, on-demand vs preconfigured).
task: definition.md
authored_by: agent
timestamp: 2026-10-06T00:34:43+02:00
---

# Exploration: 320K ctx, `--parallel 4`, unified KV, and small-context sub-agents

> **Theoretical.** Nothing here is measured yet; the empirical numbers are
> back-of-envelope from the figures already recorded in
> [`docs/local-llms.md`](../../../docs/local-llms.md) (weights ~101 GB resident,
> whole process ~115.8 GB RSS on a 125 GB box, `RssAnon` ~18 GB at 320K with
> `ubatch 4096`, prefill ~15 t/s, decode ~4-8 t/s). Every claim marked
> *verify* needs a run.

## Part 1 — `ctx-size 327680` with `--parallel 4` and `--kv-unified`

### Semantics (from llama.cpp source)

`llama-context.cpp` fixes the split:

```c
cparams.n_ctx = GGML_PAD(cparams.n_ctx, 256);
if (cparams.kv_unified) {
    cparams.n_ctx_seq = cparams.n_ctx;        // each seq may use the WHOLE pool
} else {
    cparams.n_ctx_seq = GGML_PAD(cparams.n_ctx / cparams.n_seq_max, 256);  // divided
    ...
}
```

and the graph builds one stream for the whole batch when unified:

```c
const auto n_stream = cparams.kv_unified ? 1 : ubatch.n_seqs_unq;   // llama-graph.cpp
```

So for `--parallel 4 --kv-unified --ctx-size 327680`:

- The KV **pool is 327680 tokens total**, shared by the 4 slots. It is **not**
  `4 × 320K`. Each slot may use up to the full pool while others are idle; the
  **sum over simultaneously-active sequences is bounded by 327680**.
- `n_stream = 1`, so the compute/graph buffers are sized like one sequence, not
  four — *cheaper* than the equivalent non-unified `parallel 4`.

### Memory

| item | today (`parallel 1`, non-unified, 320K) | candidate (`parallel 4`, unified, 320K) |
|---|---|---|
| weights (RssFile) | ~97 GB | ~97 GB |
| KV pool | 320K (~one context) | 320K (~one context, shared) |
| compute/graph buffer | 1 stream | 1 stream (unified) |
| `RssAnon` total | ~18 GB | ~18 GB (estimate; **verify**) |

The key result: **raising `N` does not multiply KV RAM** when unified. The pool
is one context's worth regardless of `N`. The cost of `N` is slot bookkeeping and
the shared prompt cache (`--cache-ram`, default 8 GiB) — both bounded, not `N ×`.

Caveat: today the box already sits at ~1 GB free. A few hundred MB of extra
per-slot state, or a fuller prompt cache, could tip `320K + 4 slots` into
eviction. Starting at 256K is the safe first rung. **verify.**

### Compute / throughput

- **Decode:** the server batches tokens from active slots into one forward pass.
  For a *dense* model that amortises the weight reads and aggregate throughput can
  approach `N ×`. DS4 is a sparse 284B MoE: each sequence routes to different
  experts, so the **union** of experts read per step grows with the batch, and the
  amortisation is sublinear — possibly near-flat for disjoint routings. Expect
  **aggregate decode ≈ 1.0–2× at 4 slots**, not 4×. **verify.**
- **Prefill:** mixing a prefill (compute-heavy) with another slot's decode
  (memory-heavy) improves core utilisation over serial prefill. This is where
  concurrency can help aggregate throughput, not just latency.
- **Per-request under full 4-way load:** each request roughly gets `1/N` of the
  bandwidth → ~1–2 t/s decode, ~4 t/s prefill. The win is *no head-of-line
  blocking*: four requests finish in ~the time one would have, instead of four
  serial waits.

### Context sharing under load

- Lone request: up to 327680.
- `k` concurrent requests that each want a large context: they share 327680, so
  ~`327680 / k` each. With `k = 4` that is ~81920.
- opencode prompts are ~10–20K, so `k = 4` fits 80K each comfortably. The risk is
  a single huge main-agent prompt consuming the whole pool and starving
  sub-agents.
- Mitigations (preconfigured, uniform): `--kv-unified-per-slot N` caps every slot
  at `N` tokens; with `-c` unset the pool auto-sizes to `n_parallel * N`
  (`server.cpp`: `if kv_unified_per_slot > 0 && n_ctx == 0`). Example:
  `--parallel 4 --kv-unified-per-slot 81920` → pool 327680, 80K ceiling per slot.

### DSpark interaction

`common_speculative_init(params.speculative, params.n_parallel)` is called with
`n_parallel`, so the draft is initialised for multiple sequences. Whether batched
speculative decode on CPU is efficient (or correct) in this fork is unproven.
Risk: the draft overhead per slot can exceed the single-sequence benefit, or the
combination may be unsupported. **verify** — and if it regresses, test
`--parallel 4` with the draft off.

## Part 2 — smaller-context sub-agents: client vs server

### On-demand vs preconfigured

| lever | on-demand? | where |
|---|---|---|
| a request uses only the KV it needs (shared pool) | **yes, automatic** | server (unified KV) |
| per-request context size in the API | **no such parameter** | — |
| uniform per-slot cap | no, preconfigured | server `--kv-unified-per-slot`, `--parallel` |
| a distinct provider model id + `limit.context` | no, Nix-time | client `kdn.llm.client.upstreams.<name>.models` |
| which model a sub-agent uses | no, config-time | opencode agent definition |

The two levels:

1. **Being small is automatic (on-demand).** With unified KV, a small request
   consumes only the tokens it actually sends and generates — it does not reserve
   320K. So a sub-agent that naturally has a short prompt is already cheap; no
   configuration is needed to "make it small".
2. **Being *capped* or *distinct* is preconfigured.** To guarantee a sub-agent
   cannot exceed some context, or to give it a separate label/limit, you must set
   it up ahead of time — either a uniform server-side per-slot cap, or a
   client-side model entry with a smaller `limit.context` plus an agent that
   names it.

### Server side

- **No per-request context parameter** exists in the OpenAI-compatible API, so
  the server cannot give one request a 64K slot and another 320K on demand.
- `--kv-unified-per-slot N` is a **uniform** ceiling for all slots; it cannot
  single out sub-agents. Useful as a floor of safety, not for differentiation.
- Because the pool is shared and unified, small requests are cheap without any
  flag. The flag is only needed to bound the *worst* request.

### Client side (opencode)

- The provider model list is built by `kdn.llm.client` from
  `hosts/<host>/devenv.nix`; each entry has `name`, `context`, `output`. This is
  **Nix-time configuration** (`hosts/oams/devenv.nix` currently lists
  `deepseek-v4-flash` and `frontier` at 327680).
- opencode agents/sub-agents name a `model` in their definition. Assigning a
  sub-agent a "small" model is a **config-time** choice, not a per-call one.
- **Working route to smaller-context sub-agents (preconfigured):** add a second
  provider entry that points at the *same* endpoint with a smaller
  `limit.context`, e.g. `"deepseek-v4-flash-sub"` with `context = 65536` and a
  `[64K]` label, then point the sub-agent definitions at it. The server treats an
  unknown model id by **falling back to the frontier router**
  (`packages/opencode-compat-proxy/patches/router.patch`:
  `UPSTREAMS = {"frontier": UPSTREAM}`, "anything not in the table routes to the
  frontier"), so the second id hits DS4 exactly as `deepseek-v4-flash` does — the
  only difference is the client-side context budget. This costs no extra server
  memory and needs no new server model.

### Recommended shape

- Server: `--parallel 2–4 --kv-unified`, `--ctx-size` 262144 (first rung) or
  327680 (if memory allows); optionally `--kv-unified-per-slot` as a uniform
  ceiling.
- Client: keep the main agent at the large context; add one or two smaller
  provider entries and assign the sub-agent definitions to them. This bounds what
  sub-agents send without touching the server.
- Do **not** try to express per-request context via the API — it does not exist.

## Proposed experiment (run when brys is free)

1. Add slot options `perf.kvUnified`, `perf.kvUnifiedPerSlot` (and reuse
   `perf.parallel`); mirror them in the den `llm` aspect. Pattern: `perf.batchSize`.
2. Configs to compare against the `parallel 1` baseline:
   - A: `parallel 4`, unified, `ctx 327680`, `kv-unified-per-slot 81920`.
   - B: `parallel 4`, unified, `ctx 262144`, `kv-unified-per-slot 65536`.
   - C: `parallel 2`, unified, `ctx 327680`.
3. Measure: `RssAnon`/`RssFile`/idle major faults/no-OOM; single-request
   prefill+decode; 4 concurrent requests aggregate and per-request; an
   opencode sub-agent fan-out wall time; DSpark acceptance with `parallel > 1`.
4. Decide and document in [`docs/local-llms.md`](../../../docs/local-llms.md).

## Expected outcome

- Concurrency: sub-agents stop queueing behind the main agent's prefill — the
  original symptom.
- Aggregate throughput: modest (sublinear on this MoE); the gain is latency
  isolation, not raw speed.
- Memory: roughly unchanged vs today because unified KV keeps one pool; the
  binding risk is the existing ~1 GB headroom, so `ctx 256K` is the safer start.
- Small sub-agents need **no** server change; only a client model entry if a
  guarantee/label is wanted.
