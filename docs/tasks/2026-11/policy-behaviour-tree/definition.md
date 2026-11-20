---
type: Task
description: Replace the five scattered pieces of model-placement policy on brys with one config-defined behaviour tree, evaluated by the manager, that explains every decision.
status: open
authored_by: agent
timestamp: 2026-11-20T23:10:00+01:00
---

# One placement policy, defined as a behaviour tree

## Context

The rule "which model may run beside which" is spread over five places, each with its own
semantics:

| place                                                       | decides                                        |
| ----------------------------------------------------------- | ---------------------------------------------- |
| llama-swap matrix sets (`main`, `with_co`, `with_surveyed`) | what evicts what on a request                  |
| router `modelsMax`                                          | at most one model per router                   |
| `coResidentTiers`                                           | which small models may sit beside the frontier |
| `gates` in the manager config                               | which models need a VRAM reserve               |
| `ttl` + `cmdStop` + the proxy's self-exit                   | when a model is released                       |

Two schedulers decide over one card. The audit on 2026-11-20 found what that costs:

- six of the eight surveyed models (up to 35B) have no gate, so a 35B request on `max` is
  permitted with about 1 GiB free;
- `wan-vace-14b` (28.6 GiB) plus any small model is permitted by `with_co` and does not fit;
- `qwen3.5-4b` on `max` _did_ load — it took the engine's 1 GiB reserve and put the rest on CPU,
  so oversubscription degrades silently instead of refusing.

At the same time the fleet now serves models whose requests last minutes: Qwen-Image-Edit at 20
steps is 293 s and Wan VACE is 940-1039 s per clip. The runtime's lease and drain model assumes
seconds.

## Goal

One artifact defines placement, one component evaluates it, and every decision can be explained:
which branch was taken, which numbers were used, what the resulting state would be.

## Measured facts (brys, 2026-11-20, 210 W)

| state                                          | VRAM                   |
| ---------------------------------------------- | ---------------------- |
| `qfn-max` alone                                | 30.8 GiB               |
| `qfn-fast-colo` alone                          | 10.7 GiB               |
| `qfn-fast-colo` + `qwen3-omni`                 | 30.8 GiB               |
| `qfn-fast-colo` + `qwen2.5-vl-7b`              | 20.6 GiB               |
| `qfn-fast-colo` + one small model              | 13.9 GiB               |
| `qwen-image-edit` / `longcat` / `wan-vace-14b` | 26.2 / 22.9 / 28.6 GiB |

Card: 31.86 GiB. Profile switch: 55-72 s. Frontier load: ~70 s. `sd-server` load: 3 s warm, ~40 s
cold. Leases: `leaseTTLSeconds = 1800`, `drainTimeoutSeconds = 300`.

## Design

### Input

```json
{
  "request": {
    "model": "qwen2.5-vl-7b",
    "class": "agent",
    "deadlineSeconds": 120,
    "confirm": { "kdn_switch_to": "omni-fast" }
  },
  "active": [
    {
      "model": "qfn-fast-colo",
      "kind": "engine",
      "profile": "omni-fast",
      "tier": "frontier",
      "vramMiB": 10957,
      "ramMiB": 60000,
      "loadedAt": "…",
      "loadingSince": null,
      "lastFinishedAt": "…",
      "leases": 0
    }
  ],
  "state": {
    "vramFreeMiB": 21663,
    "ramFreeMiB": 22000,
    "cacheReclaimableMiB": 40000,
    "lastSwitchAt": "…",
    "inFlight": [],
    "draining": false
  }
}
```

### Output

```json
{
  "verdict": "admit",
  "plan": { "evict": ["qwen3-omni"], "keep": ["qfn-fast-colo"], "add": ["qwen2.5-vl-7b"] },
  "resulting": { "vramMiB": 23552, "ramMiB": 91000, "decodeTps": { "qfn-fast-colo": 88.3 } },
  "why": [
    {
      "node": "b7.1",
      "verb": "pick-victim",
      "result": "success",
      "facts": { "chosen": "qwen3-omni", "idleSeconds": 940, "leases": 0 }
    }
  ],
  "explain": "admitted by evicting the companion: one model per tier, and the reviewer is smaller"
}
```

The trace is bounded (200 nodes), deterministic (tree-path ids, sorted lists) and returned on every
refusal. `/decide` is advisory and runs without the switch lock; `/admit` re-runs the tree under the
lock, because time of check is not time of use.

### The tree

Structure, order and messages are config; the verbs are Go.

```
root: selector
├─ b1  check  model-known                    → else refuse "unknown model"
├─ b2  check  already-satisfied              → serve
├─ b3  check  join-in-flight                 (loadingSince ≠ null ∨ busy) → wait ≤ deadline → serve
├─ b4  check  cooldown                       (lastSwitchAt, loadedAt + settle) → refuse "retry in Ns"
├─ b5  selector  profile-required
│   ├─ b5.1 profile met, model not loaded     → load → serve
│   ├─ b5.2 confirmed profile ∧ switch ≤ deadline → switch → load → serve
│   └─ b5.3 refuse + alternatives + confirm field
├─ b6  check  fits-beside                    (vram ∧ ram+burst ∧ speed floor) → load-beside → serve
├─ b7  selector  evict-then-load
│   ├─ b7.1 pick-victim   (tier conflict first; else oldest idle, fewest leases, smallest)
│   ├─ b7.2 check victim-idle      (leases = 0)      → else refuse "in use by N, ETA …"
│   ├─ b7.3 check victim-settled   (loadedAt age)    → else refuse "loaded 15 s ago"
│   ├─ b7.4 check victim-evictable (not persistent)  → else refuse + kdn_switch_to
│   └─ b7.5 evict → load → serve
└─ b8  action refuse with the numbers
```

Precedence rationale: join before debounce (a concurrent load is not thrash), profile before
capacity (a requirement is absolute), eviction last (it is the only branch that destroys state).

### State

| field                                                      | source                                 | decides                                          |
| ---------------------------------------------------------- | -------------------------------------- | ------------------------------------------------ |
| `vramFreeMiB`                                              | sysfs `mem_info_vram_used`             | fits, refusals                                   |
| `ramFreeMiB`, `cacheReclaimableMiB`                        | `/proc/meminfo`                        | the 95 GiB load burst                            |
| `model.vramMiB`, `ramMiB`, `loadBurstMiB`, `switchSeconds` | stage 0                                | footprints and costs                             |
| `model.loadingSince`, `loadedAt`, `lastFinishedAt`         | manager journal + `/running`           | join, amortise, idle                             |
| `model.leases`, `busySince`, `expectedSeconds`             | lease registry, activity `duration_ms` | never evict work in progress                     |
| `model.decodeTps`, `decodeWithFrontier[profile]`           | stage 0, then EWMA from activity       | speed floor                                      |
| `state.lastSwitchAt`, `inFlight`, `draining`               | manager                                | debounce, join                                   |
| `request.class`, `deadlineSeconds`                         | caller                                 | human/agent/batch priority, switch affordability |

Rejected on purpose: GTT/shared memory (discrete card), thermals and the power cap (fixed at 210 W),
disk throughput (already visible as load time), tenant identity (one human, one fleet).

## Stabilisation: attack and fix loop

Invariants, checked on every generated case:

| id  | invariant                                                                 |
| --- | ------------------------------------------------------------------------- |
| I1  | resulting VRAM ≤ budget                                                   |
| I2  | no two models of one tier                                                 |
| I3  | every model satisfies `requiresProfile`                                   |
| I4  | total: every input is admit or refuse                                     |
| I5  | every refusal is actionable                                               |
| I6  | the engine is never evicted without a profile switch                      |
| I7  | RAM + load burst fits, or refuse                                          |
| I8  | idempotence: the same request against `resulting` admits with no eviction |
| I9  | determinism: two runs, same bytes                                         |
| I11 | no plan evicts a model with `loadingSince ≠ null`                         |
| I12 | no plan starts a load already in flight                                   |
| I15 | no plan evicts a model with `leases > 0`                                  |
| I16 | idle time never includes busy time                                        |
| I17 | a busy model returns a join or a refusal with an ETA, never an eviction   |
| I19 | a renewed lease is never expired                                          |

Loop: generate `(request, active set, profile)` cases (random plus the nasty shapes: empty card,
full card, editor + companion, 35B on `max`, disallowed confirm, missing facts, unknown verb,
selector with no fallback) → classify failures → fix the tree or a verb → add the case to the
golden corpus → repeat. Exit when 10 000 consecutive generated cases add no new failure class and
the corpus is green. Then run a second-model review (`qfn` reads the tree JSON and lists
combinations that should not be permitted) and fold its findings into the corpus.

## Stages

| stage | work                                                                                                                                                                 | acceptance                                                                           |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 0     | `hack/measure-footprint.py`: VRAM, RAM, load/switch seconds, decode/prefill t/s, co-resident pairs; emit the `models` block with `measured` and `source` (file hash) | every enabled model has all numbers; the block is generated, not typed               |
| 1     | `internal/policy`: interpreter with trace, load-time validation (unknown verb refuses to start), `/decide`                                                           | five audit cases answered correctly on brys; no behaviour change                     |
| 2     | attack/fix loop                                                                                                                                                      | invariants hold on corpus + 10 000 generated cases                                   |
| 3     | `admit` wrapper on every entry, `/admit`, llama-swap matrix reduced to one set + `modelsMax = 1`                                                                     | each model class admitted or refused exactly as `/decide` predicted                  |
| 4     | eviction ownership: drop `ttl`/`cmdStop`, manager idle eviction, **lease heartbeat**, journal the trace                                                              | editor→qfn and companion→qfn still work; a 1039 s VACE job is never evicted mid-work |
| 5     | delete `gates`, `coResidentTiers`, matrix sets; second-model review                                                                                                  | one place defines policy                                                             |

## Review

**Solid.** The problem is real and measured, not hypothetical: two schedulers, six ungated 30-35B
models, one combination that cannot fit, and a 15-minute job class the runtime was not built for.
The tree shape is small (eight branches), the trace makes it testable, and every variable has a
measured source. Stages 0-2 are additive and cannot harm the box.

**Speculative.** The victim score (idle × weight − leases × weight − footprint) is a guess until the
attack loop runs; start with lexicographic ordering (tier conflict, then never-used, then oldest,
then smallest) and add weights only if a case demands them. `request.class` needs a caller contract
that does not exist yet — default everything to `agent` and add `human` when a client can say so.

**Sharp edges.** Config-defined logic invites a DSL that grows into an untested programming
language: verbs stay in Go, and the interpreter refuses to start on an unknown verb. Footprints rot
when a quant or a context changes: `measured` + `source` are load-bearing. `/decide` is advisory
and stale by design. The transition has two schedulers until stage 3, so the manager's refusal must
win and the matrix must not evict what the tree just admitted.

**The one bug this design exposed before writing a line.** A 1039 s VACE job is under the 1800 s
lease TTL, but a long prefill plus a queue is not: the lease expires, the model reads as idle, and
the next switch evicts it mid-work. The fix is a lease heartbeat, and it belongs in stage 4 —
before the editors are used for anything that matters.

**Recommendation.** Do stage 0 and 1 in one session (measure, then decide and explain, no behaviour
change), then stage 2 until the corpus is green. Do not start stage 3 until the loop has run: the
whole point is that the tree must survive being attacked before it is allowed to evict anything.

## Interim, without waiting for the tree

Two config-only changes fix the worst audit findings today:

1. gate the surveyed models above ~8 GB (`qwen3.5-35b-a3b`, `qwen3-vl-30b-a3b`,
   `ornith-1.5-35b-a3b`, `nemotron-3-nano-30b-a3b`, `lfm2.5-24b-a2b`, `mellum-2.1-12b`) with the
   companion policy, so a 35B request on `max` is a readable 409;
2. raise `leaseTTLSeconds` and add the heartbeat for batch models, so a long edit cannot be evicted
   as stale.
