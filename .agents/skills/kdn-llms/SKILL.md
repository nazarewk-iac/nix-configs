---
name: kdn-llms
description: Pick and use a model on the kdn LLM server (brys) by its stable purpose alias, and steer the engine profile (max, omni-fast, omni-max) without reloading it by accident. Use when choosing a model for a task, naming a model in opencode, asking which local model to use for chat, code, vision, audio, reasoning, tools, retrieval, or orchestration, or when a session needs the multimodal companion beside the frontier.
type: Skill
timestamp: 2026-11-22T00:00:00+01:00
---

# kdn-llms

The local LLM server runs on **brys** and is reached through the compat proxy at
`https://brys.priv.nb.net.int.kdn.im/v1` (OpenAI-compatible). opencode discovers
its models automatically (`kdn.llm.client` + `discovery.enable`), so the model
list is always the server's `/v1/models`.

Full design: [alias-scheme.design.md](../../../docs/tasks/2026-10/llm-model-expansion/alias-scheme.design.md).
Model comparison: [model-selection-guide.md](../../../docs/tasks/2026-10/llm-model-expansion/model-selection-guide.md).
Measurements: [measurements.research.md](../../../docs/tasks/2026-10/llm-benchmark-suite/001-benchmark-suite/measurements.research.md).

## How to name a model: the purpose alias

Do not name a base model id (`qwen3.5-35b-a3b`). Name a **stable purpose alias**:

```
<purpose>-<complexity>-<speed>[-<tag>][-alt]
```

- **purpose**: `chat`, `code`, `vision`, `audio`, `reason`, `tools`, `embed`,
  `rank`, `tiny`, `orchestrate`.
- **complexity**: `dumb` (mechanical, follows tight instructions, no reasoning),
  `quick` (trivial but needs a little judgment), `std` (normal), `deep` (hard,
  long, or creative).
- **speed**: `fast`, `mid`, `slow` — the latency you accept.
- **tag** (optional): `vision`, `tools`, `long`, `moe`, `gpu`, `think`.
- **-alt**: the alternate model for the slot. The bare id is the primary.

The server maps the alias to a model. To change the model, someone moves the
alias string in `data/llm.nix` (`models.<id>.aliases`) and redeploys — **the client keeps
the same id**. Never hardcode the base model name in a client config.

## Every alias is also an opencode sub-agent

On a host with the oams opencode profile, each purpose alias is registered as an
opencode **subagent** with the alias as its name (`lib/llm-agents.nix`,
generated from `data/llm.nix`). So an orchestrator delegates by naming the
alias as the Task tool's `subagent_type`:

```
Task { subagent_type: "chat-std-fast", prompt: "..." }
```

Use a concrete alias, never a family (`qwen-*` is not a valid `subagent_type`).
A subagent with no `model` inherits the caller's model, so always name one.
Full design:
[opencode-subagent-model-routing/done.md](../../../docs/tasks/2026-10/opencode-subagent-model-routing/done.md).

## Which alias to use (decide from what is live)

Pick the alias by intent, not by model. Current assignments, read from the deployed
llama-swap config on 2026-11-21:

| alias                   | use it for                 | live model                    | ctx    | speed |
| ----------------------- | -------------------------- | ----------------------------- | ------ | ----- |
| `chat-std-fast`         | normal chat/assistant      | lfm2.5-24b-a2b                | 32768  | 23    |
| `tools-std-fast`        | agent tools, RAG, terminal | lfm2.5-24b-a2b                | 32768  | 23    |
| `chat-std-mid`          | normal chat, more quality  | qwen3.5-35b-a3b               | 262144 | 23    |
| `chat-std-mid-long`     | long-context chat          | nemotron-3-nano-30b-a3b       | 32768  | 12    |
| `reason-std-fast`       | reasoning, long context    | nemotron-3-nano-30b-a3b       | 32768  | 12    |
| `reason-quick-fast`     | cheap step-by-step         | mellum-2.1-12b-a2.5b-thinking | 32768  | 14.8  |
| `reason-quick-fast-alt` | the same, smaller          | ministral-3-3b-reasoning      | 16384  | —     |
| `code-std-fast-alt`     | code, non-thinking         | mellum-2.1-12b-a2.5b-thinking | 32768  | 14.8  |
| `vision-std-fast`       | images, general            | qwen3-vl-30b-a3b              | 32768  | 15.7  |
| `vision-std-fast-moe`   | the same model, own name   | qwen3-vl-30b-a3b              | 32768  | 15.7  |
| `vision-std-fast-alt`   | images, dense text         | ornith-1.5-35b-a3b            | 32768  | 8.8   |
| `vision-deep-slow`      | hard image tasks           | ornith-1.5-35b-a3b            | 32768  | 8.8   |
| `embed-std-fast`        | embeddings (RAG)           | qwen3-embedding-4b            | 8192   | —     |
| `rank-std-fast`         | reranking (RAG)            | qwen3-reranker-4b             | 8192   | —     |

Everything else is reachable by its base id and has no alias: `gemma-4-e4b`,
`qwen2.5-vl-7b`, `qwen3-omni`, `longcat-image-edit`, `qwen-image-edit`, `wan-vace-14b`, and the
frontier names below.

**Several aliases are dead.** `chat-dumb-fast`, `chat-dumb-fast-alt`, `code-quick-fast`,
`tiny-dumb-fast`, `tiny-quick-fast` and `tools-dumb-fast` still appear in `data/llm.nix`, but
their models were pruned on 2026-11-21, so a request to one answers
`{"error":{"message":"no router for requested model"}}`. `audio-std-mid` is not in `data/llm.nix`
either, so no entry could answer it. Check before you rely on one:

```bash
curl -s https://llama-swap.brys.priv.nb.net.int.kdn.im/v1/models | jq -r '.data[].id' | sort
```

**Base ids are the safe choice for scripted work.** An alias can be re-pointed or orphaned; a base
id answers as long as its GGUF is on disk.

Rules of thumb:

- **Start with `chat-std-fast`.** Only step up to `chat-std-mid` when the task is genuinely harder,
  because the bigger models are slower and cost VRAM the frontier wants.
- **`embed-*` and `rank-*` are not chat models.** They use `/v1/embeddings` and `/v1/rerank`.
- **No purpose alias points at a frontier model.** Every alias maps to a grunt model, and every
  grunt model runs `--parallel 1`, so concurrent calls to one alias queue. Fan a fleet out across
  _different_ aliases, not many calls to one. The frontier is QFN on the Strata engine, below.
- **Some aliases share one process.** `chat-std-fast` and `tools-std-fast` are both
  `lfm2.5-24b-a2b`; `reason-std-fast` and `chat-std-mid-long` are both `nemotron-3-nano-30b-a3b`;
  `reason-quick-fast` and `code-std-fast-alt` are both `mellum-2.1-12b-a2.5b-thinking`. Treat each
  pair as one worker with one queue.

## What is registered (short summary)

Everything below is served; most carry no alias and are reachable by their base
id. Speeds are measured decode tok/s on brys.

- **Frontier**: QFN on the Strata engine, seven profiles, listed in the next section. It is not a
  llama-swap model in the usual sense: the `qfn*` entries are `strata-select` proxies.
- **Deep tier**: Requesty SaaS through the etra gateway, not on brys.
- **Live catalogue on brys (2026-11-21)**: `/v1/models` answers 35 ids — 12 base ids, 14 aliases
  and the nine frontier names. Three image editors are served but kept out of that list. The GGUF
  list is the truth; this is the shape of it.

| model                           | ctx    | role                                  |
| ------------------------------- | ------ | ------------------------------------- |
| `qwen3.5-35b-a3b`               | 262144 | biggest local chat model, MoE, 23 t/s |
| `lfm2.5-24b-a2b`                | 32768  | chat and tools workhorse, 23 t/s      |
| `nemotron-3-nano-30b-a3b`       | 32768  | reasoning and long chat, 12 t/s       |
| `mellum-2.1-12b-a2.5b-thinking` | 32768  | cheap reasoning and code, 14.8 t/s    |
| `ministral-3-3b-reasoning`      | 16384  | smallest reasoning model              |
| `gemma-4-e4b`                   | 32768  | small general model, no alias         |
| `ornith-1.5-35b-a3b`            | 32768  | best at dense terminal text, 8.8 t/s  |
| `qwen3-vl-30b-a3b`              | 32768  | vision workhorse, 15.7 t/s            |
| `qwen2.5-vl-7b`                 | 16384  | small vision model                    |
| `qwen3-omni`                    | 16384  | audio + vision + text companion       |
| `qwen3-embedding-4b`            | 8192   | embeddings                            |
| `qwen3-reranker-4b`             | 8192   | reranking                             |
| `longcat-image-edit`            | 4096   | image edit                            |
| `qwen-image-edit`               | 4096   | image edit                            |
| `wan-vace-14b`                  | 4096   | video edit                            |

The smaller grunts (`qwen3.5-0.8b/2b/4b`, `granite-4.2-3b/8b`, `tmax-*`, `gemma-4-e2b`, the CPU
variants) and every dense 27-36B model were retired on 2026-11-21 to free disk and VRAM. Their
aliases still exist in `data/llm.nix`, which is why a dead alias answers "no router".

The deep tier runs on Requesty SaaS through the etra gateway:
`requesty/deepinfra/deepseek-v4.1-flash-1017` (the pi harness default and the primary, 1M ctx),
plus the two qwen auxiliaries the pi `planner`, `reviewer` and `consultant` sub-agents use:
`requesty/alibaba/qwen3.8-flash` (1M ctx, 128K out, vision — planning) and
`requesty/tensorx/qwen3.8-flash-next` (256K/256K — review and brainstorming). All three take a
top-level `reasoning_effort`, not `chat_template_kwargs`.

Not in the catalogue, because this build cannot serve them: `ternary-bonsai-2-27b` (invalid ggml
type), parakeet ASR (unknown architecture), `minicpm-v-4.7-*` (projector unsupported).

## Working with the fleet in practice

Drawn from community evidence. Full sources:
[small-model-insights.research.md](../../../docs/tasks/2026-10/llm-model-expansion/small-model-insights.research.md)
and
[serving-ops-insights.research.md](../../../docs/tasks/2026-10/llm-model-expansion/serving-ops-insights.research.md).

**Pick the smallest model that fits the task.** Match the model to the task:
`dumb`/`quick` slots for extraction, classification, and transforms; `std` for
chat and tools. On a plain desktop, 7-8B is the general floor and about 20B the
practical ceiling; brys is a 128 GB box, so it serves larger models, fast when
MoE. The `deep` tier is SaaS only now (Frontier above): reach for it only for
long-horizon, open, or high-stakes work. Do
**not** hand a long unsupervised agent loop to a small model; that is where it
loops and drifts.

**Prompt small models tightly.** Give one clear task, the exact output shape, and
no open choices. A small model does the wrong thing _confidently_ on an open
task. Put standing rules in `AGENTS.md` or the system prompt, and scope the task
(a vague goal makes a local model read everything and hallucinate).

**Keep the context focused.** Performance falls as the input grows, and
topically-related distractors hurt most. Prefer a compact context over a large
one; summarize first and retrieve on demand. Use a `-long` alias only when the
task genuinely needs long context: a large context also slows generation and
costs KV RAM.

**Quantization.** `Q4_K_M` is the default; the quality cliff is below Q4, and Q8
is near-lossless. A low quant is fine for chat but harmful for exact work (tool
calls, literals, code). Prefer a weight quant over a KV quant. For KV, keys
matter more than values, and `q8_0` is the practical floor for tool calls (the
served Qwen at 1M already uses `q8_0` KV).

**Thinking versus fast.** Use a thinking model for hard, multi-step work, and a
fast non-thinking model for extraction, classification, and simple transforms.
Reasoning can _hurt_ extraction (extra tokens and noise). Do not set a very low
temperature on a thinking model; it loops in its think block.

**Tool calls and agents.** Tool calling needs a capable model; small ones emit a
bare tool call as plain text. Add a guardrail/retry layer and a step limit (a
retry layer lifts an 8B from about 53% to about 99% on multi-step agentic tasks).
A missing or wrong chat template makes a model silently "dumber".

**Serving and operations.**

- A MoE decodes fast because few parameters are active, but it can be more
  quant-sensitive (routing drift). Dense for quality, MoE for speed, at the same
  size.
- Prefill is compute-bound; decode is memory-bandwidth-bound. On this CPU-first
  box, decode follows memory bandwidth and prefill follows cores.
- `--parallel N` divides the context per slot, and unrelated concurrent requests
  destroy the prefix cache. Run separate servers rather than one shared server
  when you need the full context.
- Keep the system prompt stable; resending an unstable prefix is the real cost in
  an agent loop.
- Watch these failure modes: silent truncation on context overflow (use
  `--no-context-shift` to get an error), chat-template mismatch, long-context
  OOM, loops, and the W6600 GPU hang under the Vulkan draft head (keep it off).

**Watching logs and reading performance.** brys no longer runs
`llama-cpp.service`; `llama-swap.service` spawns every `llama-server` child. So:
`journalctl -u llama-swap -f` (child logs are present only with
`swap.debug = true`, which gives `logToStdout = "both"`), `journalctl -u
kdn-llm-proxy-lan -f` (the compat proxy), and on the host
`curl -s http://127.0.0.1:39700/logs` (per-model ring buffer, no history).

Per-model performance is **already exposed** — do not parse logs for it:
`GET /api/metrics/activity` returns one record per request with `model`,
`tokens.prompt_per_second`, `tokens.tokens_per_second`, `duration_ms` and the
status code; `/api/metrics/stats` aggregates them with p50/p95/p99 histograms;
`/api/captures/<id>` returns the request and response (auth redacted);
`/api/performance` gives GPU temperature, VRAM and power; `/api/hardware` gives a
full hardware inventory. All of it is in-memory and ring-buffered, so history
needs a small poller, not a log parser. `/metrics` (Prometheus) is system-only.
Full recipe: [docs/local-llms.md](../../../docs/local-llms.md#observability-and-stats).

## The engine profile: one card, one engine, and what a switch costs

On brys the frontier is **not** a llama.cpp model. One Strata engine serves QFN, and a **profile
manager** on `:8181` owns it. The profile is a start-up argument, so changing it is a **reload**,
not a slider. Seven frontier profiles, measured 2026-11-21 (the deployment serves twelve profiles
in all: these seven, two companions and three image editors):

| profile      | pack      | window × slots | single stream | aggregate | note                    |
| ------------ | --------- | -------------- | ------------: | --------: | ----------------------- |
| `max-multi`  | UD-IQ4_XS | 512k × 5       |     54–76 t/s |  31.9 t/s | **resting**             |
| `max-swarm`  | UD-IQ4_XS | 256k × 8       |             — |  36.2 t/s | most concurrent slots   |
| `max-long`   | UD-IQ4_XS | 1M × 2         |             — |  29.7 t/s | two long sessions       |
| `max-single` | UD-IQ4_XS | 1M × 1         |     61–86 t/s |         — | one big job, no sharing |
| `fast-swarm` | IQ2_XS    | 384k × 8       |             — |  61.0 t/s | lowest quality, fastest |
| `omni-max`   | UD-IQ4_XS | 1M × 1         |             — |         — | keeps a 21.5 GB reserve |
| `omni-fast`  | IQ2_XS    | 1M × 2         |             — |         — | keeps the reserve, fast |

The resting profile is **`max-multi`**: it holds 23.9 GiB of K/V, leaves the RAM floor that a build
needs, and gives five concurrent sessions a fair share. One job does **not** spread over five
slots; a slot is a concurrent request. A single stream gets the single-stream rate.

Every profile is also a llama-swap name. The alias map comes from `data/llm.nix`:

| name             | profile                                    |
| ---------------- | ------------------------------------------ |
| `qfn`            | current (`auto`, never switches)           |
| `qfn-max-multi`  | `max-multi`                                |
| `qfn-max-swarm`  | `max-swarm`                                |
| `qfn-max`        | `max-long`                                 |
| `qfn-max-long`   | `max-long`                                 |
| `qfn-max-single` | `max-single`                               |
| `qfn-fast-swarm` | `fast-swarm`                               |
| `qfn-max-colo`   | `omni-max`                                 |
| `qfn-fast-colo`  | `omni-fast`                                |
| `qwen3-omni`     | the companion, no switch, fits the reserve |

**`qfn` is the name to use.** It never switches, and a switch that somebody else starts does not cut
your request: in-flight work is drained first and a request that arrives mid-switch waits. The
other names force a profile, so a caller of one may be interrupted when somebody selects another.

### Reading and steering it

```bash
curl -s http://brys:8181/status          # profile, last switch, loaded companions
curl -s http://brys:8181/stats           # measured medians per event and per transition
curl -s -X POST http://brys:8181/select \
  -H 'Content-Type: application/json' -d '{"profile":"max-single","dry_run":true}'   # what it would cost
```

`brys:8181` is reachable from brys itself. From another host use `ssh brys -L 8181:127.0.0.1:8181`.

Rules that keep a session alive:

- **Switch between turns, never during one.** A switch stops the engine, so an in-flight request
  dies. The harness conversation survives, but the engine's KV cache does not: the next turn
  re-prefills the whole context (`200k tokens ÷ 2.8k t/s ≈ 70 s`).
- **Prefer loading the companion over switching the engine.** Inside a reserve, omni loads beside
  the running engine (+90 s once, observed) and the frontier is untouched. `POST /unload` frees its
  VRAM again with no engine reload.
- **Do not switch for a few percent.** The switch costs 58–74 s plus a re-prefill, and a switch into
  `max-single` frees 14 GiB of K/V at the cost of every other session's slot.
- **A media task inside `max-multi`** needs a colo profile: `max-multi` leaves about 8 GiB, so
  `qwen3-omni` would load slowly or be refused. Select `qfn-fast-colo` between turns.

### Two harness facts (measured 2026-11-20)

- **`opencode run` uses a background service whose environment is whichever one started it.** A key
  exported for the current process is invisible to that service, and the gateway answers
  "Invalid API key". `opencode run --standalone` starts a private server with the current
  environment and works.
- **A discovery-only provider is listed but not runnable.** `opencode models` shows what the
  discovery plugin fetched, while `opencode run --model <provider>/<id>` validates the id against
  the static catalog and answers "Model unavailable". The `qfn*` names above are declared
  statically in the client config for that reason.

### The scenario this was built for

A coding session is running. A screenshot of a BIOS/boot error arrives:

1. `POST /select {"profile":"qfn-fast-colo"}` — only if the engine is not already there (check
   `/status` first; `dry_run` says whether it would change anything). The name works as a profile
   here too.
2. Ask `qwen3-omni` for the reading. It loads beside the engine; the frontier keeps its KV.
3. `POST /unload` when the question is answered. VRAM comes back, the engine is untouched.
4. Continue coding on the same engine. Return to `qfn-max` only when the work needs the better
   pack, and do it between turns.

### Every event is timed

The manager writes one JSON line per event to `events.jsonl`: `switch` (from, to, seconds, cause),
`engine_load`, `engine_stop`, `cache_drop`, `companion_up`, `companion_down`. `GET /stats`
aggregates them (`n`, median, p90, max, per event and per transition), so an agent can quote a
measured cost instead of a guess. First measurement, 2026-11-19: switch median 42 s, `max →
omni-fast` 50 s, `omni-fast → max` 69 s, engine load 42-60 s, cache drop 4-5 s, companion load
90 s. Cumulative to 2026-11-21 (1159 events, 181 switches): switch median 54 s, `max → omni-fast`
53 s, `omni-fast → max` 76 s, engine load 51 s (p90 87), cache drop 3 s (p90 5), companion load
165 s (n=5), companion unload 0.6 s. Add a row here when a number drifts.

This skill is a **living document**. Update it as we learn, in the same change
that changes the fleet. Record:

- **Eviction behaviour**: which models evict which. The frontier is the Strata
  engine, not a llama.cpp entry in the catalogue, so it leaves the card by a
  profile switch and only the grunt tiers in `data/llm.nix` evict each other.
- **What co-resides well**: which models can run together without halving speed.
  A CPU model beside a big GPU model competes for the same ~40 GB/s of RAM
  bandwidth; a GPU grunt beside another does not.
- **Alias changes**: when an alias is re-pointed, update the table above and the
  date. An alias that no longer matches its `speed` field is a bug.
- **Load/start behaviour**: cold-load time, warm-start reuse, first-request
  stalls.
- **Quality in practice**: which model actually worked for which job, and which
  did not, from real use.

Put durable numbers in the task research files and link them here; keep this
skill short. If a learning belongs to a specific model, add one line to the
summary above and point at the research file.
