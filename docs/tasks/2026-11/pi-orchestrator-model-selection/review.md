---
type: Review
description: Independent review of the model-selection design, with each claim checked against the live fleet. Three findings were accepted, one was refuted by measurement.
task: definition.md
authored_by: agent
timestamp: 2026-11-01T22:05:00+01:00
---

# Independent review, and what it changed

Two reviewers were asked. The first (`reason-deep-slow`, high) did not finish inside 700 s on a
CPU model with a large prompt, and the second (`code-std-fast`, 32k) returned **empty** for a ~6 kB
prompt — the exact failure this task exists to fix, reproduced while reviewing it. The frontier
(`orchestrate-deep-slow`) completed and produced the review below.

## Accepted — these change the design

**A1. The catalog must reach the decider, not a sub-agent.** In engaged mode the orchestrator has
only `delegate`. A file "a sub-agent can read" is useless to the entity choosing the model.
→ **Fix:** the catalog is rendered into the orchestrator's **system prompt** (via `rules`, which
`devenv.nix` already wires), not just a file. A tool is the fallback, not the primary.

**A2. `/running` reports base model ids, not aliases.** Verified: it returns
`north-mini-code-1.0`, `qwen3.8-flash-next`. The alias→id map lives in `/v1/models`
`meta.llamaswap.modelID`, so the join is a **second request**, not free.
→ **Fix:** the status tool does both requests and returns alias-keyed state; the research file
claimed this was one call and is corrected.

**A3. The context filter cannot be enforced by prompt alone.** The orchestrator hands a *task
text* to `delegate`; it cannot know in advance that the sub-agent will open a 468 KB file.
→ **Fix:** move the gate into the tool. `delegate` gains an optional `inputBytes` argument; the
extension **rejects** a delegation whose declared input exceeds the target model's served context
(and says which alias would fit). Plus a cheap `measure` action that returns a file's size, so the
orchestrator never has to guess. Prompt rules stay, but a rule nobody can violate beats a rule
nobody follows.

## Refuted by measurement — do not change

**R1. "`/metrics` is process-level, not host-level"** — **false.** Measured on `brys`:
`llamaswap_memory_total_bytes` = **134 968 508 416** (125 GiB, the host total) and
`llamaswap_load_average{1m}` = **14.6** against host `/proc/loadavg` = **13.43**. The families are
host-scoped. The headroom design stands.

## Noted, and deliberately accepted as caveats

| # | Caveat | Why we accept it |
|---|---|---|
| C1 | A client alias choice cannot stop llama-swap evicting the frontier | It is a hint by design; the matrix owns eviction. The value is *avoiding* a bad request, not controlling the server. |
| C2 | `loadSeconds` / `tokensPerSecond` are static and will drift | Accept. They are hints with an order-of-magnitude purpose (1 s vs 90 s), not predictions. Marked as estimates in the catalog. |
| C3 | `capabilities.strengths` duplicates the alias naming | Accept but narrow: keep only what the alias cannot say — `operation` (cpu/gpu) and `loadSeconds`. Drop `strengths`. |
| C4 | "Escalate after two failures" needs per-tier state | Accept: the orchestrator's own context *is* the state within a session. Documented, not hidden. |
| C5 | Three TLS GETs under 3 s may fail exactly under load | Accept, and it is why the tool must always return the **static** view plus a `stale: true` flag rather than an error. |
| C6 | `proof-context-filter.md` could be satisfied by the model merely saying "I reject this" | Accept the criticism. The proof must show the **rejection is emitted by code**, with the exit path and message, not by prose. |
| C7 | llama-swap's eviction/matrix policy is opaque here | Accept. Recorded as a caveat; the task does not depend on modelling it. |

## Verdict adopted

The review's central point is right and is now the core of the design: **the one mechanism that
would have prevented the 2 h 24 min incident is a programmatic size gate, and the rest is advisory
data.** Parts 1, 2 and 3 stay, reordered so the gate is Part 1.
