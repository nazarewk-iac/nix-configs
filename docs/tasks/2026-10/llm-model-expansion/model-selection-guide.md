---
type: Reference
description: Plain-language guide to every measured local-LLM candidate on brys, for a reader new to LLMs: what each model is good for, its pros and cons, and a ranked shortlist per size and speed bucket.
timestamp: 2026-10-20T22:30:00+02:00
---

# Which model to pick: a plain-language guide

This is a decision aid, not a benchmark. It groups every measured model on brys
into **speed buckets** and **size buckets**, and says what each is good for. All
speed numbers are measured on brys (AMD Ryzen 5950X, 128 GB RAM, one 8 GB AMD
W6600; CPU-only unless noted). Full numbers: [measurements.research.md](../tasks/2026-10/llm-benchmark-suite/001-benchmark-suite/measurements.research.md)
and the `docs/tasks/2026-10/llm-model-expansion/` files.

## Read this first: three words

- **tok/s (tokens per second)** — speed. One token is about ¾ of a word. For
  chat, 15 tok/s reads comfortably; 5 tok/s feels slow; 2 tok/s is a coffee
  break. Prefill (reading your prompt) is separate and usually much faster.
- **Dense vs MoE** — a **dense** model uses all of its weights for every token,
  so speed scales with size. A **MoE** model activates only a small part per
  token, so a 30B MoE can run as fast as a 3B dense. On this machine, MoE is
  almost always the better deal.
- **Grunt vs orchestrator** — a **grunt** does small, well-scoped jobs fast. An
  **orchestrator** (the big frontier model) plans, reviews, and decides.

Two **frontier** models (DeepSeek V4 Flash, Qwen3.8-Flash-Next) are the heavy
orchestrators. They are slow and only one fits in RAM at a time. Everything else
below is a grunt or a specialist.

## Speed buckets (measured decode)

| bucket | speed | what it is for |
|---|---|---|
| **Blazing** | 80-210 tok/s | instant, tiny models; classifiers, quick rewrites |
| **Fast** | 20-80 tok/s | comfortable chat and most grunt work |
| **Usable** | 8-20 tok/s | larger MoE, solid quality, still fine for chat |
| **Slow** | 5-8 tok/s | big dense/MoE; batch work, not interactive |
| **Crawl** | < 5 tok/s | only worth it for quality or a rare task |

## Size buckets and the rankings

### Tiny (0.5-3 GB) — Blazing or Fast

| model | size | decode | good for | weak at |
|---|---|---|---|---|
| **qwen3.5-0.8b** | 0.5 GB | 208 | classification, routing, tiny rewrites; runs on the GPU | anything needing knowledge or reasoning |
| **qwen3.5-2b** | 1.2 GB | 120 | fast grammar work, tagging, first-pass drafts | complex logic |
| **tmax-2b** | 1.3 GB | 120 | same class as qwen3.5-2b | same |
| **lfm2.5-2.6b** | 1.6 GB | 14 | on-device tool use, terminal command chains, RAG steps | coding, general knowledge |
| **granite-4.2-3b** | 2.1 GB | 85 | fast general chat, good tool-calling for its size | deep reasoning |
| **ministral-3-3b-instruct** | 2.2 GB | 79 | quick chat, summarising; GPU-fit | long context |
| **qwen3.5-4b** | 2.6 GB | 61 | strong small general model, the default small grunt | hard reasoning |

**Pick:** `qwen3.5-4b` as the everyday small grunt (best all-round tiny).
`qwen3.5-0.8b` when you want pure speed.

### Small (3-6 GB) — Fast

| model | size | decode | good for | weak at |
|---|---|---|---|---|
| **gemma-4-e2b** | 3.1 GB | 105 | very fast general chat, image-capable | deep tasks |
| **granite-4.2-8b** | 5.0 GB | 39 | IBM's tool-calling; enterprise/agent workflows | independent proof is thin |
| **ministral-3-8b-instruct** | 5.2 GB | 38 | balanced small chat | jargon-heavy domains |
| **ministral-3-8b-reasoning** | 5.2 GB | 39 | small step-by-step reasoning | slower than the plain model for simple tasks |
| **mimo-v2.6-qwen-9b** | 5.5 GB | 35 | fast 9B general chat | niche brand, less proven |
| **tmax-9b** | 5.6 GB | 37 | fast 9B general chat | niche brand |
| **ornith-1.5-9b** | 5.4 GB | 7.2 | **vision** at 9B (image understanding) | coding; slow for its size |
| **qwen3-vl-8b** | 5.0 GB | 8.4 | vision: OCR, captions, image Q&A | coding; slow decode |

**Pick:** `granite-4.2-8b` for tool-calling, `ministral-3-8b-instruct` for general
chat. For **vision**, see the vision section below.

### Mid (7-17 GB) — Fast to Usable

| model | size | decode | good for | weak at |
|---|---|---|---|---|
| **mellum-2.1-12b-a2.5b** | 7.5 GB | 14.8 | fast reasoning sub-agent; JetBrains code-tuned | unreliable tool calls; not a primary coder |
| **gemma-4-12b** | 7.1 GB | 18.5 | multimodal (image + audio), laptop-class quality | agentic tool use |
| **muse-glimmer-30b** | 14.8 GB | 1.9 | schema-driven tool use on a small GPU | long unsupervised agent runs; very slow here |
| **lfm2.5-24b-a2b** | 14.5 GB | 23 | **fastest big model**: RAG, terminal chains, tool use | coding, general knowledge |
| **qwen3.8-27b** | 16.5 GB | 2.45 | **vision + strong chat + tool-calling**, one model | slow on CPU; offline trivia weak |
| **qwen3.6-27b** | 16.8 GB | 3.1 | proven daily driver, vision | superseded by 3.8 |
| **jirackdeltanet-27b** | 15.7 GB | 2.2 | experiment; little independent proof | unclear lineage, thin coverage |

**Pick:** `lfm2.5-24b-a2b` for speed at mid size, `qwen3.8-27b` for quality+
vision. `mellum` for a cheap fast reasoner.

### Large (17-25 GB) — Usable to Slow

| model | size | decode | good for | weak at |
|---|---|---|---|---|
| **glm-4.7-flash** | 18.3 GB | 20.2 | fast 30B MoE general chat | tool-calling broke in early builds |
| **qwen3.5-35b-a3b** | 22.0 GB | 23 | fast 35B MoE general chat | its dense sibling is better |
| **qwen3.6-35b-a3b** | 22.1 GB | 22.3 | fast 35B MoE, vision | — |
| **nemotron-3.5-lightning-30b** | 25.0 GB | 20.4 | fast 30B MoE general chat | niche |
| **qwen3-vl-30b-a3b** | 18.6 GB | 15.7 | **vision (MoE), best speed for a VLM** | not a coder |
| **qwen3-omni-30b-a3b** | 18.6 GB | 8.8 | **audio + vision + text** in one server | slower; custom license |
| **north-mini-code-1.0** | 18.6 GB | 18.0 | **code specialist**, fast, tool use | harness may break its tool calls |
| **qwen3-coder-30b-a3b** | 18.6 GB | 9.1 | pure-Qwen **coder**, best prefill | no thinking mode; older |
| **tiel-coder-35b-a3b** | 22.7 GB | 6.7 | fast local **coding** | support uncertain; needs a fork |
| **nemotron-3-nano-30b-a3b** | 24.6 GB | 12.1 | long-context reasoning/research | weak multi-step agentic coding |
| **qwen3-vl-32b** | 19.8 GB | 2.2 | vision (dense, higher quality) | very slow decode |
| **qwq-32b** | 19.9 GB | 1.65 | dedicated reasoner (older) | superseded; language-mixing |
| **granite-4.2-30b** | 17.7 GB | 3.0 | IBM agentic workflows | thin independent proof |
| **gemma-4-31b** | 18.3 GB | 2.8 | strong dense multimodal | slow, no agentic tool use |
| **olmo-3.1-32b** | 19.5 GB | 2.7 | fully-open research/reasoning | weak tool-calling |
| **seed-oss-36b** | 21.8 GB | 2.4 | budgeted reasoning | thin coverage |
| **ornith-1.5-35b-a3b** | 21.7 GB | 8.8 | **vision MoE**, good speed+vision | coding |
| **swift-1.5-qwen3.8-27b** | 11.0 GB | 2.0 | low-quant merge of 3.8-27B | a merge, not a new base |

**Best large picks:** `qwen3.5-35b-a3b` / `qwen3.6-35b-a3b` (fast general),
`glm-4.7-flash` (fast general), `qwen3-vl-30b-a3b` (vision), `north-mini-code-1.0`
(code), `nemotron-3-nano-30b-a3b` (long context).

### Specialists (any size)

| model | size | good for | note |
|---|---|---|---|
| **qwen3-embedding-4b** | 2.3 GB | retrieval (RAG) — turns text into vectors | serves `/v1/embeddings`, dim 2560 |
| **qwen3-reranker-4b** | 2.3 GB | reranking search results | serves `/v1/rerank` only |
| **mellum-2.1-12b** | 7.5 GB | code (thinking) | see mid bucket |
| **hy-memory-30b-a3b** | 17.0 GB | writing an agent's long-term memory store | not a chat model |
| **gemma-4-12b** | 7.1 GB | image + audio understanding | see mid bucket |

## Recommendation: a small, useful fleet

If you want to keep only a handful, this set covers almost every job:

1. **`qwen3.5-4b`** — the fast everyday grunt (61 tok/s). Non-negotiable.
2. **`lfm2.5-24b-a2b`** — the fast big generalist (23 tok/s). Best speed/brain trade.
3. **`qwen3.5-35b-a3b`** (or `glm-4.7-flash`) — a heavier generalist when quality
   matters (20-23 tok/s).
4. **`north-mini-code-1.0`** — the code specialist (18 tok/s).
5. **`qwen3-vl-30b-a3b`** — vision, at good speed (15.7 tok/s).
6. **`qwen3-omni-30b-a3b`** — audio + vision, if you want speech in (8.8 tok/s).
7. **`qwen3-embedding-4b`** + **`qwen3-reranker-4b`** — retrieval for RAG.
8. The two **frontier** models — the orchestrators, one resident at a time.

That is 8 grunts/specialists plus 2 orchestrators.

## What to drop first (least useful on this machine)

- **Slow dense models with no unique role:** `qwq-32b` (1.65 tok/s), `qwen3-vl-32b`
  (2.2), `seed-oss-36b` (2.4), `olmo-3.1-32b` (2.7), `gemma-4-31b` (2.8),
  `granite-4.2-30b` (3.0), `muse-glimmer-30b` (1.9). The MoE models are faster and
  mostly as good.
- **Duplicated roles:** `qwen3.6-27b` vs `qwen3.8-27b` (keep 3.8);
  `qwen3.5-35b-a3b` vs `qwen3.6-35b-a3b` (keep one);
  `jirackdeltanet-27b`, `swift-1.5` (merges/experiments, thin proof).
- **Broken on this build:** `ternary-bonsai-2-27b` (invalid ggml type),
  `parakeet` ASR (unknown architecture). Do not keep.
- **MiniCPM-V-4.7** (1B and 35B): the vision projector is unsupported, so it is
  text-only. No advantage over Qwen3-VL.

## Caveats

- Speed is CPU-only in the tables. The small models (<= about 6 GB) run on the
  8 GB GPU and are faster than shown; the 30B+ models are CPU-only.
- The 30B-MoE decodes (18-23 tok/s) are real and measured, but they read a lot of
  RAM per token, so they slow down if a frontier model shares the box.
- "Weak at coding" or "weak at chat" is what reviewers report, not a rigorous
  test. Treat it as a starting point.
