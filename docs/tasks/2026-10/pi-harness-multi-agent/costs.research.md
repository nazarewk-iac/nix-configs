---
type: Research
description: Where Pi reports token usage and cost, why a local model costs zero money but real wall time, per-agent aggregation, and the accounting table a fleet evaluation needs.
task: definition.md
authored_by: agent
timestamp: 2026-10-28T11:45:00+01:00
---

# Pi token usage, cost reporting, and the multi-agent accounting model

Draft for the Pi harness on this homelab. Read-only research; no repo changes.

## 0. Versions and how to read the citations

| Version | What it is | Where |
|---|---|---|
| **1.4.0** | Upstream docs, the authoritative spec for the current API | `https://raw.githubusercontent.com/earendil-works/pi/v1.4.0/packages/coding-agent/docs/<file>.md` |
| **1.1.0** | The installed CLI (`pi --version` → `1.1.0`); the code claims below are checked against its shipped `dist/` | `/nix/store/yyrq47f5z3rpzax1ka5znmn2fj5kfkha-pi-coding-agent-1.1.0/lib/node_modules/pi-monorepo/` |
| **0.85.1** | Local vendored docs, cross-check only | `/nix/store/qf702rins357mp8jlr1s5k1s3kp2d2ms-pi-coding-agent-0.85.1/lib/node_modules/pi-monorepo/docs/` |

Every claim names its source. Claims checked only against 1.1.0 `dist/` say so. The live `brys` probe could **not** be run from this host (`oams`: `curl 127.0.0.1:39700` refused; no local llama-swap), so any "what brys returns" statement is either from the repo's own verified `docs/local-llms.md` / `b-stats.md`, or marked **not verified**.

`pi run` is **not** a subcommand: `pi run --help` (1.1.0) prints the top-level help. Use `pi -p "…"` / `pi --mode json`.

## 1. The usage fields Pi emits, and where they live

The canonical shape is one object, `Usage`, attached to every assistant message (and to summarization/cache entries):

```ts
// v1.4.0 session-format.md:107-117 and v0.85.1 session-format.md:103-116 (identical)
interface Usage {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  totalTokens: number;
  cost: {
    input: number; output: number; cacheRead: number; cacheWrite: number; total: number;
  };
}
```

`cost` is a **nested object with `.total`**, not a scalar. That matters for every consumer: the subagent example reads `usage.cost?.total` (see §4).

### 1a. `--mode json` event stream

Source: `v1.4.0 json.md:95-99` (same example in 1.1.0 `docs/json.md:98`):

```json
{"type":"message_update","usage":{"input":100,"output":1,"cacheRead":0,"cacheWrite":0,"totalTokens":101,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}},"assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hello "}}
```

`json.md:95` says: "The top-level `usage` is the latest cumulative provider-reported usage for the assistant response. It can remain zero until completion when a provider does not report usage while streaming."

The **authoritative** value is `message_end.message.usage` (`json.md:68`: "`message_end` | `message` | A message completed. This is the authoritative final message."). `turn_end` carries `message` + `toolResults` (`json.md:58`); `agent_end` carries `messages` + `willRetry` (`json.md:55`). Per-turn delta accounting must key on `message_end` where `message.role === "assistant"`, not on `message_update`.

`tool_execution_end` carries `durationMs` (`json.md:107`) — wall time of the tool's `execute()`, not model time. Do not count it as token cost, but do count it in wall-clock (see §8).

### 1b. Session file (JSONL)

Source: `v1.4.0 session-format.md:11` — path is
`~/.pi/agent/sessions/--<path>--/<timestamp>_<session-id>.jsonl`.
Assistant messages carry the model and the full `usage` (`session-format.md:91`):

```json
{"type":"message","id":"b2c3d4e5","parentId":"a1b2c3d4","timestamp":"…","message":{"role":"assistant","content":[…],"api":"anthropic-messages","provider":"anthropic","model":"claude-sonnet-4-5","usage":{…},"stopReason":"stop","timestamp":1733234402000}}
```

Three more entry kinds contribute usage and **must be counted** (they cost real tokens but are not assistant turns):

- `UsageEntry` — `{"type":"usage",…,"kind":"cache_warm","provider":…,"usage":{…}}`; "Usage entries contribute to session token and cost totals" (`session-format.md:113-121`).
- `CompactionEntry.usage` — the LLM call that generated the summary (`session-format.md:135`).
- `BranchSummaryEntry.usage` — the `/tree` summary call (`session-format.md:160`).

Pi's own aggregator groups them: `getUsageCostBreakdown` buckets assistant messages by `provider/model`, `usage` entries by `provider/model`, and tool-results + `branch_summary`/`compaction` under the literal key `"Tools/summaries"` (1.1.0 `dist/core/usage-totals.js:45-73`).

### 1c. `/stats`-style command

There is **no `/stats` command** in 1.1.0 or 1.4.0. There is `/session`:
`v1.4.0 usage.md:62` and `sessions.md:16`: "`/session` shows its file, ID, message count, token usage, and cost." The TUI footer also shows "accumulated usage and cost" (`usage.md:9`). `/session` is interactive-only; it is not a machine-readable channel.

### 1d. `--export`

`--export <file>` writes **HTML** and exits (`v1.4.0 cli.md:39`, `cli.md` option table). There is no JSON export, so `--export` is not an accounting channel. Whether the HTML embeds usage is **not verified** (not needed for this design).

### 1e. Server-side (the ground truth you already have)

`docs/local-llms.md:137` (repo, verified on brys): `/api/metrics/activity` gives per request
`tokens.{input,output,cache,draft,draft_acc}`, `tokens.prompt_per_second`, `tokens.tokens_per_second`, `duration_ms`, `has_capture`, `metadata.fifo_priority`.
`local-llms.md:151` warns: "`duration_ms` … is wall clock and **includes the model load**, so it is not a pure inference time." And `local-llms.md:234-246`: the compat-proxy must pass `stream_options.include_usage` or the client counter stays at zero.

Pi does request it: 1.1.0 `dist/…/pi-ai/dist/api/openai-completions.js:583`
`if (compat.supportsUsageInStreaming !== false) params.stream_options = { include_usage: true };`
So a compatible brys endpoint that honours `include_usage` will populate Pi's `usage`. If a model's `compat.supportsUsageInStreaming` is set `false` in `models.json`, Pi stops requesting it and the usage will be zero — **do not set that flag for brys models**.

## 2. Is `cost` real for a local OpenAI-compatible endpoint (brys)?

**No. It is numerically present and always zero for a model with no price table.** Three independent proofs:

1. Docs statement — `v1.4.0 models.md:182`:
   > "The cost uses the model's catalog price; models without one, such as TypeSafe's direct `jev-latest`, report tokens at no cost."
2. Custom models default to zero rates — 1.1.0 `dist/core/provider-composer.js:107`:
   ```js
   cost: definition.cost ?? { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
   ```
   A model added to `models.json` without a `cost` block (the normal local setup, `models.md:49-63`) therefore has all-zero rates.
3. The cost is computed from those rates — 1.1.0 `dist/…/pi-ai/dist/models.js:658-676`:
   ```js
   export function calculateCost(model, usage) {
     const inputTokens = usage.input + usage.cacheRead + usage.cacheWrite;
     let rates = model.cost;
     ...
     usage.cost.input  = (rates.input  / 1000000) * usage.input;
     usage.cost.output = (rates.output / 1000000) * usage.output;
     ...
     usage.cost.total  = usage.cost.input + usage.cost.output + usage.cost.cacheRead + usage.cost.cacheWrite;
   }
   ```
   With `rates = {0,0,0,0}`, every field and `total` is `0`.

And the usage object is **always initialized with a zero cost object** before `calculateCost` runs — 1.1.0 `dist/…/pi-ai/dist/api/openai-completions.js:1180-1190` (`parseChunkUsage`):
```js
const usage = { input, output, cacheRead, cacheWrite, reasoning: …,
  totalTokens: input + outputTokens + cacheReadTokens + cacheWriteTokens,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
calculateCost(model, usage);
```

So the answer to "zero, null, or omitted" is: **zero**, never `null`, never omitted. Downstream code even tolerates omission (`usage.cost?.total || 0`, §4), but Pi does emit the object.

**Consequence for this homelab:** Pi's `cost.total` on the brys fleet is worthless as money. It is a faithful *"if this were billed at catalog price"* field, which is exactly why it must be kept separate from the paid overseer's dollars (§8). If a notional local price is ever wanted, put a `cost` block on the brys model definitions in `models.json` (1.1.0 `dist/core/model-config.js:160-177`: `cost` is an optional `ModelCostSchema` on a model definition, per-million-token rates) and then `calculateCost` will produce it — but that is fiction unless you deliberately price the homelab.

**Live-level check: not verified.** I could not send a request to brys from `oams`. The code path above is from the installed 1.1.0 binary and is deterministic; the only assumption is that the brys model is declared without `cost`, which is the documented local setup.

## 3. `contextTokens` and compaction

### 3a. What `contextTokens` is

Pi computes a context size from the last good assistant usage — 1.1.0 `dist/bundle/chunks/chunk-OIM2DMFI.js` (`calculateContextTokens`):
```js
function calculateContextTokens(usage){ return usage.totalTokens || usage.input+usage.output+usage.cacheRead+usage.cacheWrite }
```
and `estimateContextTokens` adds a char-based estimate for messages after that usage point (`trailingTokens`). In the JSON stream the raw `usage.totalTokens` is `input+output+cacheRead+cacheWrite` for that response (`parseChunkUsage`, §2).

The **subagent example's** `usage.contextTokens` is *not* this estimate: it is simply the last assistant message's `totalTokens` (see §4, `currentResult.usage.contextTokens = usage.totalTokens || 0`). Use it as "context after the last turn", not as "tokens before the next request".

### 3b. Compaction trigger

`v1.4.0 compaction.md:32-35`:
```
contextTokens > contextWindow - reserveTokens
```
Defaults (`compaction.md:36`, `compaction.md:55`): `reserveTokens = 16384`, `keepRecentTokens = 20000`. The same defaults are hard-coded in 1.1.0 `dist/bundle/chunks/chunk-OIM2DMFI.js`:
```js
var DEFAULT_COMPACTION_SETTINGS={enabled:!0,reserveTokens:16384,keepRecentTokens:2e4};
function shouldCompact(contextTokens,contextWindow,settings){ return settings.enabled ? contextTokens>contextWindow-settings.reserveTokens : !1 }
```

### 3c. Disable / tune per run

Settings file (`v1.4.0 settings.md:69-76`, and 1.1.0 `dist/core/settings-manager.js:621-658`):

| Key | Default | Effect |
|---|---|---|
| `compaction.enabled` | `true` | `false` disables auto-compaction entirely (`shouldCompact` returns false). `/compact` still works manually. |
| `compaction.reserveTokens` | `16384` | Trigger headroom. |
| `compaction.keepRecentTokens` | `20000` | Recent tokens kept unsummarized. |
| `compaction.modelOverrides` | none | Per `provider/modelId` overrides of the two numbers. |

Set them in `~/.pi/agent/settings.json` or `<project>/.pi/settings.json`. **There is no per-invocation CLI flag** for compaction; a run's compaction policy is the settings file's. An extension can intercept via `session_before_compact` and cancel (`compaction.md`, "Custom Summarization via Extensions"), which is the only per-run override.

For the harness: run each worker with a **fixed, small** context policy (e.g. `compaction.enabled=false` and a deliberate model switch, or a high `reserveTokens`) so that a worker's accounting does not silently include a summarizer call. If compaction is left on, its usage lands in `CompactionEntry.usage` / the `compaction_end.result.usage` event (`json.md:138-155`) and must be attributed to the run.

## 4. Per-agent accumulation in the subagent example

Source: `v1.4.0 examples/extensions/subagent/index.ts` (1036 lines, fetched). The mechanism is: **spawn one `pi` per agent in `--mode json`, parse `message_end`, sum `usage` per assistant message.**

Spawn args (`subagent.ts:296`):
```ts
const args: string[] = ["--mode", "json", "-p", "--no-session"];
...
if (model) args.push("--model", model);
if (agent.tools?.length) args.push("--tools", agent.tools.join(","));
...
args.push(`Task: ${task}`);
```

The aggregation (`subagent.ts:363-374`):
```ts
if (msg.role === "assistant") {
  currentResult.usage.turns++;
  const usage = msg.usage;
  if (usage) {
    currentResult.usage.input      += usage.input      || 0;
    currentResult.usage.output     += usage.output     || 0;
    currentResult.usage.cacheRead  += usage.cacheRead  || 0;
    currentResult.usage.cacheWrite += usage.cacheWrite || 0;
    currentResult.usage.cost       += usage.cost?.total || 0;
    currentResult.usage.contextTokens = usage.totalTokens || 0;
  }
  if (!currentResult.model && msg.model) currentResult.model = msg.model;
  if (msg.stopReason) currentResult.stopReason = msg.stopReason;
}
```

Note the three asymmetries that matter:
- `cost` is summed as `cost.total` (the scalar), into a flat `usage.cost` number.
- `contextTokens` is **overwritten** each turn (latest), not summed — it is a gauge, not a counter.
- `turns` counts assistant messages, i.e. model responses, not tool calls.

Per-mode accumulation:

- **Single** (`subagent.ts:716-745`): one `runSingleAgent`, one `SingleResult`.
- **Chain** (`subagent.ts:566-597`): `results.push(result)` per step; each `runSingleAgent` computes its own totals. `previousOutput = getFinalOutput(result.messages)` feeds the next step.
- **Parallel** (`subagent.ts:607-700`): `mapWithConcurrencyLimit(..., MAX_CONCURRENCY=4, ...)` (line 634), one `runSingleAgent` per task; `allResults[index] = result`.

The run-level total is a pure sum over per-result usages (`subagent.ts:849-859`):
```ts
const aggregateUsage = (results: SingleResult[]) => {
  const total = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, turns: 0 };
  for (const r of results) {
    total.input += r.usage.input;
    total.output += r.usage.output;
    total.cacheRead += r.usage.cacheRead;
    total.cacheWrite += r.usage.cacheWrite;
    total.cost += r.usage.cost;
    total.turns += r.usage.turns;
  }
  return total;
};
```
Used for the "Total:" footer in chain/parallel/single detail rendering (`subagent.ts:916, 937, 1001, 1025`). `details.results` (with full messages) is the persisted tool result; `usage` is only the compact summary.

**Important:** the subagent example uses `--no-session` (line 296), so this path is stdout-only. Your zellij-pane children will *not* have that (§5).

## 5. Cheapest per-turn usage for a zellij-pane child

The child runs interactively in a zellij pane, so stdout is the TUI, not JSONL. The result channel is the **session file**. Cheapest correct approach:

1. Give the pane a deterministic session id: `pi --session-id <run>.<agent> --session-dir <harness-dir> …` (`v1.4.0 cli.md`, `--session-id` / `--session-dir`; `pi --help` 1.1.0 confirms both).
2. At (or after) the run, read `<harness-dir>/--*--/<ts>_<id>.jsonl` and one-pass `jq`:
   - assistant turns: `select(.type=="message" and .message.role=="assistant") | .message.usage`
   - summarizer/cache: `select(.type=="compaction" or .type=="branch_summary") | .usage`
   - cache warming: `select(.type=="usage") | .usage`
3. That is one file read and no extra process. It is cheaper than (a) `zellij action dump-screen` + scrape, (b) re-running `--mode json` after the fact, (c) RPC.

Why not RPC: `--mode rpc` gives events on stdin/stdout, which would again be the pane's stream and needs a second protocol client. Why not `--export`: HTML only (§1d). Why not `/session`: interactive text only.

If the child *can* be driven non-interactively, `--mode json` + parse is strictly better (structured, no file scan), which is what the subagent example does. For a pane you keep interactive, the session file is the cheapest and it is complete.

Caveat: session entries are a **tree**. Sum only the active branch, or sum all — for cost you want **all** assistant messages ever produced (abandoned branches did cost tokens). Pi's own `getUsageCostBreakdown` walks entries and does not filter by branch, so "sum every assistant `usage` in the file" matches Pi's `/session` total. Use that.

## 6. Non-output tokens that still cost time/money

These are all **prefill**, not output. Pi persists them verbatim in the first system message, so they are measurable from the session file without re-tokenizing the repo.

The structured prompt sections (1.1.0 `dist/core/system-prompt.js:70-128`):
`preamble`, `tools` (tool snippets), `rules`, `docs`, `addendum` (`--append-system-prompt`), `project_context` (AGENTS.md/CLAUDE.md), `skills`, `cwd`, plus any custom section. Tool declarations also persist as `toolsAdded[].description` + `parameters` (`v1.4.0 session-format.md:80-84`).

| Contributor | Where it is stored | How to measure |
|---|---|---|
| Base preamble, rules, docs | first `role:"system"` entry, `sections.preamble/rules/docs` | length of each string |
| AGENTS.md / CLAUDE.md | `sections.project_context` | length |
| Skill files loaded | `sections.skills` (+ each skill's own file only when read by a tool) | length |
| Tool descriptions + JSON schemas | `toolsAdded[]` on the same entry | `JSON.stringify(toolsAdded).length` |
| Images | history entries | Pi estimates 4800 chars each |

Pi's own estimator is a **chars/4** approximation (1.1.0 `dist/bundle/chunks/chunk-OIM2DMFI.js`, `estimateTokens2`):
```js
Math.ceil(chars/4)   // text; images count as 4800 chars; system includes sections + JSON.stringify(toolsAdded)
```
So you can compute a per-section token estimate from the session file with the same rule and stay consistent with Pi's compaction math.

The **cross-check** for the sum is the first assistant turn's `usage.input + usage.cacheRead + usage.cacheWrite` (the whole prefill) and, on the server, llama-swap's `tokens.input_tokens` (`docs/local-llms.md:137`). Note the two are not identical in definition: Pi's `input` excludes cache reads/writes (`parseChunkUsage` subtracts them, §2), whereas brys' `input_tokens` is the raw prompt count. Reconcile as `pi_input + pi_cacheRead + pi_cacheWrite ≈ brys_input_tokens`.

## 7. What is *not* measurable from Pi alone

- **Queue wait / cold-load time**: `duration_ms` on the server includes load (`local-llms.md:151`); Pi has no field for it. Must come from brys `/api/metrics/activity` + `/api/events` `inflight` (`b-stats.md §2`).
- **GPU occupancy / power**: brys `/api/performance` (`local-llms.md:138`), not in Pi.
- **Decode vs prefill split**: Pi only has `usage`; tok/s split is server-side (`prompt_per_second`, `tokens_per_second`, `local-llms.md:137`).
- **Per-section bill**: Pi never attributes cost to sections; only the total prefill is billed.

## 8. Proposed accounting model

### 8.1 Two currencies, never mixed

| Class | Counters | Unit | Sources |
|---|---|---|---|
| **Local** (brys fleet) | tokens in/out/cache, wall seconds, GPU-seconds, queue seconds, prefill/decode tok/s | time + tokens | Pi `usage` + `message_end` timestamps; brys activity/performance |
| **Paid** (overseer, escalation, any SaaS) | tokens in/out/cache, **USD** | money | Pi `cost.total` (catalog price is real here) |

Rule: a report has two subtotals, `local` and `paid`. Never add a local `cost.total` to a paid `cost.total`. Local `cost.total` is `0` and carries no information (§2); a *notional* USD (`tokens × catalog rate`, or a deliberately set `models.json` `cost`) may be printed as a secondary figure but never in the spend column.

### 8.2 Per-agent-turn record

One JSONL line per assistant message (plus one per summarizer/cache call). Field names mirror Pi where possible.

| Field | Type | Source |
|---|---|---|
| `v` | int | schema version (`1`) |
| `kind` | `"turn"` | literal |
| `run_id` | string | harness |
| `agent_id` | string | `orch`, `worker:<name>#<i>`, `overseer` |
| `role` | enum | `orchestrator｜worker｜overseer｜summarizer` |
| `provider`,`model`,`alias` | string | Pi `message.provider/model`; brys `modelStatus.aliases` (`b-stats.md §3`) |
| `local` | bool | `provider ∈ {brys, llama-swap}` |
| `session_id`,`entry_id` | string | session header + entry `id` |
| `turn_index` | int | count within session |
| `ts_start`,`ts_end`,`wall_ms` | time | `turn_start`…`message_end`; fallback entry timestamps |
| `ttft_ms` | int? | **not verified** — no Pi field; from server `inflight.upsert` elapsed if joined |
| `usage.input/output/cacheRead/cacheWrite/totalTokens` | int | Pi `usage` |
| `usage.cost.total` | number | Pi (`0` when local) |
| `reasoning_tokens` | int? | Pi `usage.reasoning` (1.1.0 `parseChunkUsage`) |
| `context_tokens` | int | last `totalTokens` (gauge, §3a) |
| `compaction` | `null｜{reason,tokensBefore,usage}` | `compaction_end` / `CompactionEntry` |
| `stop_reason` | string | `message.stopReason` |
| `tool_calls` | int | count in `message.content` |
| `server` | object? | join: `{activity_id, prompt_per_second, tokens_per_second, duration_ms, load_ms, gpu_util}` |
| `outcome` | enum | `ok｜error｜aborted｜length` |

### 8.3 Per-run record

| Field | Meaning |
|---|---|
| `run_id`,`task`,`agents` | identity |
| `turns` | Σ per-turn |
| `local_tokens{in,out,cache_r,cache_w}` | local subtotal |
| `paid{tokens{…},usd}` | paid subtotal (real money) |
| `wall_s` | critical-path wall time (spawn → settle) |
| `sum_agent_compute_s` | Σ per-agent wall (parallel work counted once each) |
| `gpu_seconds` | Σ `wall × occupancy` |
| `queue_s` | Σ cold-load/FIFO wait from brys |
| `quality` | `q ∈ [0,1]` from the evaluation rubric (tests pass fraction / judge score) |
| `rework_p` | measured or `1-q` |
| `cost_cs` | compute-seconds, §8.5 |
| `efficiency` | `q / cost_cs` |
| `outcome` | final |

### 8.4 Cost of a local fleet: seconds, not dollars

Local "cost" is a vector, reported as-is:
- **wall-clock seconds** — what the user waits;
- **decode tok/s** (`tokens_per_second`) and **prefill tok/s** (`prompt_per_second`) — throughput;
- **queue wait seconds** — cold load + FIFO, the hidden latency (`duration_ms` includes load);
- **GPU-seconds** = `wall_s × occupancy` — the scarce resource (one GPU, N models);
- optional **joules** = `power_W × wall_s` from `/api/performance`.

Do not collapse these into one fake dollar. Collapse them into *one comparable number* only inside the evaluation formula below, and keep the vector alongside.

### 8.5 "Cost of a delegation" formula

Goal: make a slow-but-good orchestrator comparable with a fast-but-wrong worker.

Define **compute-seconds** (`cs`), a single unit for both classes:
```
C_turn = W + α·G + β·Q + γ·P
  W = wall seconds of the turn
  G = GPU-seconds (wall × occupancy)
  Q = queue/load seconds
  P = paid USD (0 for local)
  α = 0.5   (GPU is shared; α<1 avoids double counting when serial)
  β = 0.25  (idle wait is cheap but not free)
  γ = 3600 / r_ref,  r_ref = reference $/GPU-hour (e.g. 0.50 → 7200 cs per $1)
```

Then the **cost of a delegation** includes the coordinator's own work, integration, and the risk of redoing it:
```
C_del = C_plan + Σ_workers C_worker + C_integrate + (1 - q)·C_rework
  C_plan, C_integrate = orchestrator turns spent composing/reading the task
  C_rework = measured mean cost of a failed delegation (fallback: C_del itself)
  q = worker quality, 0..1
```

**Efficiency** (higher is better, comparable across models and fleet sizes):
```
E = q / max(C_del, ε)
```
Two agents are directly comparable: a fast-wrong worker with `q=0.4` and a slow-good one with `q=0.9`.
Worked example (same `C_rework = 180 cs`):
- O: `W=120, q=0.9` → `C = 120 + 0.1·180 = 138`, `E = 0.9/138 = 0.0065`
- F: `W=20,  q=0.4` → `C = 20  + 0.6·180 = 128`, `E = 0.4/128 = 0.0031`
O wins despite 6× the wall time. Raise `C_rework` (a costly downstream step) and the gap widens; set `C_rework=0` (isolated benchmark, no downstream) and F wins — which is correct, and shows why the formula needs the evaluation's rework cost, not the benchmark's.

For a run with parallel workers, report both `wall_s` (critical path) and `Σ C_worker` (total compute); they answer different questions ("how long" vs "what it consumed"). Use `Σ` in `C_del`, `wall_s` in latency SLAs.

### 8.6 Where to log

Three sinks, consistent with the existing collector:

1. **Pi-side per-turn** — harness writes `~/.local/state/<harness>/turns/YYYY-MM-DD.jsonl`, one line per §8.2 record. For `--mode json` children, emit on `message_end`; for zellij-pane children, derive by tailing the session file (§5). Always include the session `entry_id` so a line is idempotent.
2. **Server-side** — the existing `llm-stats-collector` on brys writes `/var/lib/llm-stats/requests/YYYY-MM-DD.jsonl` with the fields already designed in `b-stats.md §A` (`ts,id,generation,host,model,aliases,routing_version,input_tokens,output_tokens,cache_tokens,draft_tokens,draft_acc_tokens,prompt_per_second,tokens_per_second,duration_ms,status,…`). Do **not** duplicate that; consume it.
3. **Evaluation report** — aggregates §8.3 per run, split local/paid, computing `C_del` and `E`.

Join gap (mark): Pi does not receive the llama-swap `activity.id`, and the server does not receive Pi's `entry_id`. Join on `(host, model, ts ±1 s, input/output token pair)` — good enough for reports, not for billing. The clean fix (out of scope, requires repo change) is a proxy-injected `X-Request-ID` echoed by Pi into the session — **not implemented**.

Do not use Pi's `cost` for local, do not use brys `duration_ms` as inference time, and do not compare tok/s across models without the prefill/decode split.

## 9. Answers in one place

1. **Fields**: nested `Usage{input,output,cacheRead,cacheWrite,totalTokens,cost{…,total}}`; in JSON `message_update.usage` / authoritative `message_end.message.usage`; in session assistant `message.usage` plus `usage`/`compaction`/`branch_summary` entries; `/session` + footer; `--export` is HTML only.
2. **Local cost**: zero for any model without a price table (`models.md:182`; `provider-composer.js:107`; `calculateCost` → 0). Never null, never omitted.
3. **Compaction**: triggers at `contextTokens > contextWindow - reserveTokens` (16384), keeps 20k; disable with `compaction.enabled=false`, tune `reserveTokens`/`keepRecentTokens`/`compaction.modelOverrides`; no CLI flag, per-run override only via an extension.
4. **Aggregation**: spawn `pi --mode json -p --no-session`, on each assistant `message_end` add `input/output/cacheRead/cacheWrite`, add `cost.total`, set (overwrite) `contextTokens`; chain sums per step, parallel sums per task, both via `aggregateUsage` (§4 quotes).
5. **Zellij child** (cheapest): deterministic `--session-id` + one `jq` pass over the session JSONL summing every assistant/summarizer/cache `usage`.
6. **Non-output tokens**: persisted `sections.*` + `toolsAdded[]`; measurable by length at chars/4; cross-check first-turn prefill and brys `input_tokens`.

## 10. Open / not verified

- Live brys round-trip for `cost=0` and `include_usage` — **not verified** (no local llama-swap on `oams`); derived from 1.1.0 code + docs.
- `ttft_ms` from Pi — no field; would need server `inflight` join.
- `--export` HTML containing usage — **not verified**.
- Pi↔llama-swap shared request id — **not present**; join is heuristic.
- 1.4.0 vs 1.1.0 divergence in this area: docs examples are identical; the `Usage` shape is unchanged from 0.85.1; **no divergence found** in the fields above.

## 11. Sources

- Docs (v1.4.0): `json.md`, `session-format.md`, `sessions.md`, `usage.md`, `models.md`, `settings.md`, `compaction.md`, `cli.md`, `sdk.md` — `https://raw.githubusercontent.com/earendil-works/pi/v1.4.0/packages/coding-agent/docs/<file>.md`.
- Subagent example (v1.4.0): `…/examples/extensions/subagent/index.ts` (`:296`, `:363-374`, `:566-597`, `:607-700`, `:849-859`).
- Installed 1.1.0 code: `dist/…/pi-ai/dist/models.js:658-676`, `…/api/openai-completions.js:583,1180-1190`; `dist/core/provider-composer.js:107`, `dist/core/usage-totals.js:45-73`, `dist/core/settings-manager.js:621-658`, `dist/core/system-prompt.js:70-128`, `dist/bundle/chunks/chunk-OIM2DMFI.js` (`DEFAULT_COMPACTION_SETTINGS`, `estimateTokens2`).
- Vendored 0.85.1: `docs/session-format.md:103-116` (cross-check only).
- Repo: `docs/local-llms.md:125-165,234-246`; `/tmp/opencode/agents/b-stats.md`; `docs/tasks/2026-10/llm-metrics-persistence/api-surface.research.md`.
