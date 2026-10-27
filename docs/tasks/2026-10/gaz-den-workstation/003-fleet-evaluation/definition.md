---
type: Task
description: Measure how to drive real work with the local brys fleet: which alias per task class, which models co-run, the practical concurrency, and the points where a slow orchestrator plus cheap workers wins or loses.
status: open
authored_by: agent
timestamp: 2026-10-27T19:45:00+01:00
---

# Evaluate the fleet while it does the job

Part of [../definition.md](../definition.md).

## Why this cannot be a benchmark

A benchmark measures one request at one size. An agent workload is a chain:
plan, delegate, read, fix, retry. The costs that matter are the ones a benchmark
omits — queueing behind `--parallel 1`, a model swap that takes 90 s, a `dumb`
worker that returns a confident wrong answer and costs a whole extra turn.

The `gaz` conversion is a real chain with real failure modes. Measuring it in
flight is the honest test, and it costs nothing extra because the work happens
anyway.

## Questions to answer

1. **Which alias for which job?** Per task class (one-line edit, multi-file
   refactor, shell step, screenshot reading, config review), which is the
   cheapest alias that succeeded, and how often did the first attempt fail?
2. **What runs at the same time?** The measured answer, not the theoretical one.
   The config says every non-frontier model is `--parallel 1`, and four aliases
   share the `qwen3.5-4b` process. What does that mean for a five-way fan-out?
3. **Does the GPU grunt buy real concurrency?** `qwen3.5-4b` is on Vulkan0, so it
   should not steal CPU bandwidth from the frontier. Measure the frontier's
   decode rate with the grunt idle, busy, and absent.
4. **How much VRAM is actually loadable?** 15 models share 8 GB. Find the real
   set that fits together.
5. **When is the orchestrator the bottleneck?** Qwen at high thinking is ~2.5
   t/s with a 1M context. How long is a typical decision turn? Does the plan
   survive a 25-minute turn?
6. **How often is the overseer needed?** Count oracle calls per phase, and what
   kind. This is the cost of a local orchestrator, in a currency we care about.
7. **Where does it break?** Every OOM, every eviction, every loop, every stall.

## Method

Record per turn, in `.worklog.md` (git-ignored), one line:

```
<ts> phase=<n> alias=<alias> task=<3-word slug> secs=<n> verdict=ok|wrong|partial retries=<n> note=<short>
```

Record per cycle the health numbers from
[../design.md](../design.md#4-the-watch-loop), and per event the swap and
eviction lines from the swap journal.

Then aggregate into:

| Table | Columns |
|---|---|
| By alias | calls, success on first try, median seconds, typical use |
| By task class | cheapest sufficient alias, escalations, failures |
| Concurrency | the largest genuinely parallel set observed, and its effect on the frontier |
| Frontier | decode t/s and TTFT with the grunt idle / busy / absent |
| Orchestrator | median decision turn, longest turn, oracle calls, loops |
| Incidents | every OOM, eviction, stall, and their wall-clock cost |

## Constraints

- Do not run a synthetic load test that displaces the real work. Append small
  probes only, and only between phases.
- Every number carries the model id it was measured on. An alias can be
  re-pointed on the server without warning; the alias alone is not a
  measurement.
- An estimate is labelled an estimate. The `colocation.research.md` arithmetic
  is a ceiling, not a measurement.

## Acceptance

- Every table is filled from real data, or marked "not observed".
- The answer to question 1 is a short decision table an orchestrator can follow.
- The answer to question 2 and 3 is numeric and reproducible (the command and the
  observed output are quoted).
- The run's incidents are listed with their cost.
- The `kdn-llms` skill is updated with anything durable that was learned.
