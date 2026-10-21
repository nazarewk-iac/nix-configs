---
name: kdn-llms
description: Pick and use a model on the kdn LLM server (brys) by its stable purpose alias. Use when choosing a model for a task, naming a model in opencode, or asking which local model to use for chat, code, vision, audio, reasoning, tools, retrieval, or orchestration.
type: Skill
timestamp: 2026-10-20T23:45:00+02:00
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
alias string in `hosts/brys/llm-routers.nix` and redeploys — **the client keeps
the same id**. Never hardcode the base model name in a client config.

## Which alias to use (decide from what is live)

Pick the alias by intent, not by model. Current assignments:

| alias | use it for | live model | speed |
|---|---|---|---|
| `chat-dumb-fast` | rewrite/classify/extract, simple Q&A | qwen3.5-4b | 61 |
| `chat-quick-fast` | short general chat | qwen3.5-4b | 61 |
| `chat-std-fast` | normal chat/assistant | lfm2.5-24b-a2b | 23 |
| `chat-std-mid` | normal chat, more quality | qwen3.5-35b-a3b | 23 |
| `chat-std-mid-long` | long-context chat | nemotron-3-nano-30b-a3b | 12 |
| `chat-deep-slow` | hard/creative questions | qwen3.8-27b | 2.5 |
| `code-quick-fast` | tiny code edits | qwen3.5-4b | 61 |
| `code-std-fast` | normal coding | north-mini-code-1.0 | 18 |
| `code-deep-slow` | hard coding | qwen3.8-27b | 2.5 |
| `vision-quick-fast` | quick image Q&A / OCR | qwen3-vl-8b | 8.4 |
| `vision-std-fast` | images, general | qwen3-vl-30b-a3b | 15.7 |
| `vision-deep-slow` | hard image tasks | qwen3.8-27b | 2.5 |
| `audio-std-mid` | speech in (audio+vision+text) | qwen3-omni-30b-a3b | 8.8 |
| `reason-quick-fast` | cheap step-by-step | mellum-2.1-12b | 14.8 |
| `reason-std-fast` | reasoning, long context | nemotron-3-nano-30b-a3b | 12.1 |
| `reason-deep-slow` | hard reasoning | qwen3.8-27b | 2.5 |
| `tools-dumb-fast` | mechanical tool calls | granite-4.2-3b | 85 |
| `tools-std-fast` | agent tools, RAG, terminal | lfm2.5-24b-a2b | 23 |
| `tools-deep-slow` | hard agent tasks | qwen3.8-27b | 2.5 |
| `embed-std-fast` | embeddings (RAG) | qwen3-embedding-4b | — |
| `rank-std-fast` | reranking (RAG) | qwen3-reranker-4b | — |
| `tiny-dumb-fast` | routing/classification | qwen3.5-0.8b | 208 |
| `tiny-quick-fast` | fastest general | qwen3.5-4b | 61 |
| `orchestrate-deep-slow` | plan/review, 1M ctx, vision | qwen3.8-flash-next | 2.5 |
| `orchestrate-deep-slow-alt` | plan/review, 320K ctx | deepseek-v4-flash | 1.5 |

Each slot also has an `-alt` id where one exists (`chat-dumb-fast-alt`,
`tools-std-fast-alt`, `vision-std-fast-alt`, `code-std-fast-alt`,
`reason-quick-fast-alt`). Use `-alt` when the primary is busy or you want a
different trade.

Rules of thumb:

- **Start with `chat-std-fast` or `tiny-quick-fast`.** Only step up to `std`/`deep`
  when the task is genuinely harder, because the `deep` models are ~10-25x slower.
- **Never use a `dumb` slot for anything open-ended.** `dumb` models obey tight
  instructions and fail (confidently) on ambiguity.
- **`embed-*` and `rank-*` are not chat models.** They use `/v1/embeddings` and
  `/v1/rerank`.
- **The two `orchestrate-deep-slow*` models are heavy** and only one fits in RAM
  at a time. Reaching one evicts the other.

## What is registered (short summary)

Everything below is served; most carry no alias and are reachable by their base
id. Speeds are measured decode tok/s on brys (CPU-only).

- **Frontier / orchestrate**: `qwen3.8-flash-next` (1M ctx, vision), `deepseek-v4-flash` (320K).
- **Fast 30-35B MoE (20-23 t/s)**: `qwen3.5-35b-a3b`, `qwen3.6-35b-a3b`, `glm-4.7-flash`, `nemotron-3.5-lightning-30b`, `lfm2.5-24b-a2b`.
- **Quality 27-32B dense (2-3 t/s)**: `qwen3.8-27b`, `qwen3.6-27b`, `gemma-4-31b`, `granite-4.2-30b`, `olmo-3.1-32b`, `seed-oss-36b`.
- **Multimodal**: `qwen3-vl-30b-a3b`, `qwen3-vl-8b-instruct`, `ornith-1.5-35b-a3b` (all vision), `qwen3-omni-30b-a3b` (audio+vision), `gemma-4-12b/26b-a4b/e2b/e4b` (image+audio).
- **Code**: `north-mini-code-1.0`, `qwen3-coder-30b-a3b`.
- **Reasoning**: `mellum-2.1-12b-a2.5b`, `nemotron-3-nano-30b-a3b`, `ministral-3-3b-reasoning`.
- **Tools**: `granite-4.2-3b`, `granite-4.2-8b`.
- **Retrieval**: `qwen3-embedding-4b`, `qwen3-reranker-4b`.
- **Small GPU grunts (35-208 t/s)**: `qwen3.5-0.8b/2b/4b`, `tmax-2b/9b`, `granite-4.2-3b/8b`, `ministral-3-3b/8b-*`, `mimo-v2.6-qwen-9b`, `olmo-3-7b-instruct`, `gemma-4-e2b/e4b`.
- **CPU variants**: `qwen3.5-0.8b-cpu`, `qwen3.5-2b-cpu`, `tmax-2b-cpu`.

Measured but **not** registered: `muse-glimmer-30b`, `minicpm-v-4.7-*` (projector
unsupported), `hy-memory-30b-a3b`, `qwq-32b`, `jirackultra-1b`,
`jirackdeltanet-27b`, `swift-1.5`, `gemma-4-12b-qat`. Broken on this build:
`ternary-bonsai-2-27b` (invalid ggml type), parakeet ASR (unknown architecture).

## Keeping this skill current

This skill is a **living document**. Update it as we learn, in the same change
that changes the fleet. Record:

- **Eviction behaviour**: which models evict which. brys holds one frontier
  model at a time; the two `orchestrate` models evict each other. Note any
  grunt that evicts the frontier (it should not: grunts are `evict_cost = 1`).
- **What co-resides well**: which models can run together without halving speed.
  A CPU grunt beside the frontier competes for the same ~40 GB/s of RAM
  bandwidth; a GPU grunt does not.
- **Alias changes**: when an alias is re-pointed, update the table above and the
  date. An alias that no longer matches its `speed` field is a bug.
- **Load/start behaviour**: cold-load time, warm-start reuse, first-request
  stalls.
- **Quality in practice**: which model actually worked for which job, and which
  did not, from real use.

Put durable numbers in the task research files and link them here; keep this
skill short. If a learning belongs to a specific model, add one line to the
summary above and point at the research file.
