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
<purpose>-<complexity>-<speed>[-<tags>]
```

- **purpose** — the job: `chat`, `code`, `vision`, `audio`, `reason`, `tools`,
  `rag`, `embed`, `rank`, `tiny`, `orchestrate`.
- **complexity** — how hard: `quick` (trivial), `std` (standard), `deep`
  (hard or long).
- **speed** — the latency class you accept: `fast` (interactive), `mid`
  (seconds), `slow` (a minute or more is fine).
- **tags** — optional qualities: `vision`, `tools`, `long`, `moe`, `gpu`,
  `think`.

The client picks an id; the alias resolves to a model. `speed` states intent,
and the served model may exceed or miss it. The measured decode of the assigned
model is in the table, so the promise is checkable.

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

`<id>` -> assigned model, with the model's measured decode. "alt" is the model to
move the alias to when the first is busy or you want more quality.

### chat — everyday Q&A and writing

| id | assigned model | decode | alt |
|---|---|---|---|
| `chat-quick-fast` | `qwen3.5-4b` | 61 | `qwen3.5-2b` |
| `chat-std-fast` | `lfm2.5-24b-a2b` | 23 | `qwen3.5-35b-a3b` |
| `chat-std-mid` | `qwen3.5-35b-a3b` | 23 | `glm-4.7-flash` |
| `chat-deep-slow` | `qwen3.8-27b` | 2.45 | `deepseek-v4-flash` |

### code — code generation and edits

| id | assigned model | decode | alt |
|---|---|---|---|
| `code-quick-fast` | `qwen3.5-4b` | 61 | `granite-4.2-3b` |
| `code-std-fast` | `north-mini-code-1.0` | 18 | `qwen3-coder-30b-a3b` |
| `code-deep-slow` | `qwen3.8-27b` | 2.45 | `deepseek-v4-flash` |

### vision — images

| id | assigned model | decode | alt |
|---|---|---|---|
| `vision-quick-fast` | `qwen3-vl-8b` | 8.4 | `gemma-4-e2b` |
| `vision-std-fast` | `qwen3-vl-30b-a3b` | 15.7 | `ornith-1.5-35b-a3b` |
| `vision-deep-slow` | `qwen3.8-27b` | 2.45 | `qwen3-vl-32b` |

### audio — speech in

| id | assigned model | decode | alt |
|---|---|---|---|
| `audio-std-mid` | `qwen3-omni-30b-a3b` | 8.8 | — |

### reason — step-by-step sub-agent

| id | assigned model | decode | alt |
|---|---|---|---|
| `reason-quick-fast` | `mellum-2.1-12b-a2.5b` | 14.8 | `ministral-3-3b-reasoning` |
| `reason-std-fast` | `nemotron-3-nano-30b-a3b` | 12.1 | `qwen3.5-35b-a3b` |
| `reason-deep-slow` | `qwen3.8-27b` | 2.45 | `deepseek-v4-flash` |

### tools — agent tools, function calling, RAG steps

| id | assigned model | decode | alt |
|---|---|---|---|
| `tools-quick-fast` | `granite-4.2-3b` | 85 | `qwen3.5-4b` |
| `tools-std-fast` | `lfm2.5-24b-a2b` | 23 | `granite-4.2-8b` |
| `tools-deep-slow` | `qwen3.8-27b` | 2.45 | `deepseek-v4-flash` |

### rag — retrieval pipeline

| id | assigned model | endpoint | alt |
|---|---|---|---|
| `rag-embed` | `qwen3-embedding-4b` | `/v1/embeddings` | — |
| `rag-rank` | `qwen3-reranker-4b` | `/v1/rerank` | — |

### tiny — always-on, latency-first

| id | assigned model | decode | alt |
|---|---|---|---|
| `tiny-quick-fast` | `qwen3.5-0.8b` | 208 | `qwen3.5-2b` |
| `tiny-std-fast` | `qwen3.5-4b` | 61 | `granite-4.2-8b` |

### orchestrate — the heavy planners

| id | assigned model | note |
|---|---|---|
| `orchestrate-deep-slow` | `qwen3.8-flash-next` | 1M context, vision |
| `orchestrate-deep-slow-ds4` | `deepseek-v4-flash` | 320K context |

Two orchestrator ids, because only one fits in RAM at a time and they differ in
context and quality.

## Tagged variants (optional)

A tag narrows an id without a new complexity or speed. Use them only when a real
need appears.

| id | meaning | assigned model |
|---|---|---|
| `chat-std-mid-long` | long-context chat | `nemotron-3-nano-30b-a3b` |
| `code-std-fast-moe` | fast MoE coder | `north-mini-code-1.0` |
| `vision-std-fast-moe` | fast MoE VLM | `qwen3-vl-30b-a3b` |
| `chat-deep-slow-think` | thinking on | `qwen3.8-27b` (thinking) |

## How to implement

1. Add the id string to the assigned model's `aliases` list in
   `hosts/brys/llm-routers.nix` (or `hosts/brys/llm.nix` for the frontier).
2. Redeploy the `llms-frontier` specialisation.
3. Confirm the id appears in `/v1/models` with the right `context_length`.
4. To re-point an id, move the string to a different model's `aliases`, and
   remove it from the old one.

An alias adds no KV cap and no memory on its own; it is a routing name. Context
still comes from the base model, so a `-long` tag must point at a model whose
served context is actually long.

## Notes

- The scheme replaces the earlier client-side context tiers. Those bounded the
  request size; these name an intent. They can coexist, but do not mix them in
  one id.
- The two frontier aliases `frontier` and `qwen` already exist and stay as
  short compatibility names.
- Every assigned model above is measured on brys; see
  [model-selection-guide.md](model-selection-guide.md) and the measurement files
  in this directory.
