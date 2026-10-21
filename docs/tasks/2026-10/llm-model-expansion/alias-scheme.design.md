---
type: Design
description: A stable server-side alias scheme of the form `<purpose>-<complexity>-<speed>[-<tags>]`, so an opencode client keeps one model id per intent while the served model is swapped underneath without a client change.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T23:15:00+02:00
---

# Stable purpose aliases for the brys fleet

## Idea

The client requests a **stable id that names an intent**, not a model. The server
maps that id, as a llama-swap alias, to whatever model currently best serves the
intent. To change the model, move the alias to a different model in
`hosts/brys/llm-routers.nix` (`aliases = [ "<id>" ]`) and redeploy. No client
change, no `opencode.jsonc` edit, no subagent change.

This reuses the existing mechanism: each model may carry `aliases = [ ... ]`,
llama-swap routes the alias to that model, and `includeAliasesInList = true`
makes every alias appear in `/v1/models`, so discovery finds them.

## The name

```
<purpose>-<complexity>-<speed>[-<tag>][-alt]
```

- **purpose** — the job: `chat`, `code`, `vision`, `audio`, `reason`, `tools`,
  `embed`, `rank`, `tiny`, `orchestrate`. (`rag` is not a purpose: it is the
  pipeline `embed` -> search -> `rank` -> generate, and the generate step uses a
  normal `chat-*` or `tools-*` id.)
- **complexity** — how much capability the task needs:
  - `dumb` — mechanical. Follow a simple, tightly-specified instruction (rewrite
    this, extract this field, classify this, call this tool in this shape). No
    reasoning, no creativity. A `dumb` model is fast and predictable, and it
    fails on open-ended tasks.
  - `quick` — trivial, but needs a little judgment.
  - `std` — normal work.
  - `deep` — hard, long, or creative. Needs the strongest model.
- **speed** — the latency class you accept: `fast` (interactive), `mid`
  (seconds), `slow` (a minute or more is fine).
- **tag** — optional quality: `vision`, `tools`, `long`, `moe`, `gpu`, `think`.
- **-alt** — optional suffix that names the alternate model for the slot.

The client picks an id; the alias resolves to a model. `speed` states intent,
and the served model may exceed or miss it. The measured decode of the assigned
model is in the table, so the promise is checkable.

The **bare** id (`chat-std-fast`) is the primary. `-alt` names the second
choice. There is no `-main` suffix: the bare id is the main.

## Rules

1. **One alias, one model.** llama-swap rejects two models that claim one alias.
2. **The alias must be a real server id.** The compat-proxy routes an unknown id
   to the frontier upstream but does not rewrite it, and llama-server then
   rejects it with HTTP 400. An alias satisfies this rule.
3. **Stable ids, swappable models.** The id is a contract. Change the model, not
   the id. If a model's speed no longer matches the `speed` field, either move
   the alias to a faster model or add a new id.
4. **No context tiers in the name.** A context tier is an alias too, but it is
   not a purpose. Keep context tiers separate if wanted; do not overload the
   purpose id.

## The scheme applied

Each row is one alias id, the model it currently resolves to, and that model's
measured decode on brys. The `-alt` id resolves to the alternate model for the
slot. A bare id is the primary; there is no `-main`.

Models marked "(new)" are downloaded and measured but not yet registered; this
change registers them.

### chat — everyday Q&A and writing

| id | model | decode |
|---|---|---|
| `chat-dumb-fast` | `qwen3.5-4b` | 61 |
| `chat-dumb-fast-alt` | `granite-4.2-3b` | 85 |
| `chat-quick-fast` | `qwen3.5-4b` | 61 |
| `chat-std-fast` | `lfm2.5-24b-a2b` (new) | 23 |
| `chat-std-mid` | `qwen3.5-35b-a3b` | 23 |
| `chat-deep-slow` | `qwen3.8-27b` | 2.45 |
| `chat-deep-slow-alt` | `deepseek-v4-flash` | 1.46 |

### code — code generation and edits

| id | model | decode |
|---|---|---|
| `code-quick-fast` | `qwen3.5-4b` | 61 |
| `code-std-fast` | `north-mini-code-1.0` (new) | 18 |
| `code-std-fast-alt` | `qwen3-coder-30b-a3b` (new) | 9.1 |
| `code-deep-slow` | `qwen3.8-27b` | 2.45 |

### vision — images

| id | model | decode |
|---|---|---|
| `vision-quick-fast` | `qwen3-vl-8b` (new) | 8.4 |
| `vision-std-fast` | `qwen3-vl-30b-a3b` (new) | 15.7 |
| `vision-std-fast-alt` | `ornith-1.5-35b-a3b` (new) | 8.8 |
| `vision-deep-slow` | `qwen3.8-27b` | 2.45 |

### audio — speech in

| id | model | decode |
|---|---|---|
| `audio-std-mid` | `qwen3-omni-30b-a3b` (new) | 8.8 |

### reason — step-by-step sub-agent

| id | model | decode |
|---|---|---|
| `reason-quick-fast` | `mellum-2.1-12b-a2.5b` (new) | 14.8 |
| `reason-quick-fast-alt` | `ministral-3-3b-reasoning` | 81 |
| `reason-std-fast` | `nemotron-3-nano-30b-a3b` (new) | 12.1 |
| `reason-deep-slow` | `qwen3.8-27b` | 2.45 |

### tools — agent tools, function calling

| id | model | decode |
|---|---|---|
| `tools-dumb-fast` | `granite-4.2-3b` | 85 |
| `tools-std-fast` | `lfm2.5-24b-a2b` (new) | 23 |
| `tools-std-fast-alt` | `granite-4.2-8b` | 39 |
| `tools-deep-slow` | `qwen3.8-27b` | 2.45 |

### embed — retrieval embeddings

| id | model | endpoint |
|---|---|---|
| `embed-std-fast` | `qwen3-embedding-4b` (new) | `/v1/embeddings` |

### rank — retrieval reranking

| id | model | endpoint |
|---|---|---|
| `rank-std-fast` | `qwen3-reranker-4b` (new) | `/v1/rerank` |

### tiny — always-on, latency-first

| id | model | decode |
|---|---|---|
| `tiny-dumb-fast` | `qwen3.5-0.8b` | 208 |
| `tiny-dumb-fast-alt` | `qwen3.5-2b` | 120 |
| `tiny-quick-fast` | `qwen3.5-4b` | 61 |

### orchestrate — the heavy planners

| id | model | context |
|---|---|---|
| `orchestrate-deep-slow` | `qwen3.8-flash-next` | 1M, vision |
| `orchestrate-deep-slow-alt` | `deepseek-v4-flash` | 320K |

Two orchestrator ids, because only one fits in RAM at a time.

## Tagged variants (optional)

A tag narrows an id without a new complexity or speed. Use a tag only when a
real need appears. The `-alt` suffix stays last.

| id | meaning | model |
|---|---|---|
| `chat-std-mid-long` | long-context chat | `nemotron-3-nano-30b-a3b` |
| `code-std-fast-moe` | fast MoE coder | `north-mini-code-1.0` |
| `vision-std-fast-moe` | fast MoE VLM | `qwen3-vl-30b-a3b` |
| `chat-deep-slow-think` | thinking on | `qwen3.8-27b` |

## How to implement

1. Register each "(new)" model in `hosts/brys/llm-routers.nix` (the `surveyed`
   set) with `hfRepo = "surveyed"`, `download.enable = false`, and a `perf`
   block.
2. Attach the ids: add the id string to the assigned model's `aliases` list.
   An alias is a routing name; it adds no KV cap and no memory.
3. The frontier ids go in `hosts/brys/llm.nix` (`frontierModels`/`qwenModels`).
4. Redeploy the `llms-frontier` specialisation.
5. Confirm every id appears in `/v1/models` with the right `context_length`.

A `-long` tag only works if the assigned model's served context is actually
long, because an alias adds no context of its own.

## Notes

- The scheme replaces the earlier client-side context tiers. Those bounded the
  request size; these name an intent. Do not mix the two in one id.
- The frontier aliases `frontier` and `qwen` already exist and stay as short
  compatibility names.
- Every assigned model is measured on brys; see
  [model-selection-guide.md](model-selection-guide.md).
