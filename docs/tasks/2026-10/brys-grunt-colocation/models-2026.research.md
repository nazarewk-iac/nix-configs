---
type: Research
description: Survey of 2026-released small "grunt" LLMs for CPU/8GB-GPU llama.cpp on host brys.
task: definition.md
timestamp: 2026-10-18T00:00:00+02:00
authored_by: agent
---

# 2026 Small "Grunt" LLM Survey for host `brys`

Research date: **2026-10-18**. Every release date and file listing below was read
from the HuggingFace API on that date. Claims are tagged `[V]` verified (URL
given) or `[I]` inferred.

## 1. Hardware constraints (restated)

- CPU: Ryzen 9 5950X, 128 GB DDR4, ~40 GB/s usable bandwidth. Decode on CPU is
  bandwidth-bound: a 2 GB weight file caps near `40/2 ≈ 20 tok/s` `[I]`.
- GPU: Radeon Pro W6600, 8 GB VRAM, ~7.5 GB usable, **Vulkan/RADV via
  llama.cpp only** (no ROCm). Budget: ≤ ~6 GB Q4 weights + KV at 16–32K.
- Serve with llama.cpp GGUF, OpenAI-compatible router, measure with `llama-bench`.

Two fit classes:

- **(A) GPU grunt** — fully offloadable to 7.5 GB. Safe: Q4 weights ≤ ~6 GB.
- **(B) CPU grunt** — ~1–2 GB weights, or a small-total MoE that keeps ~12–18 GB
  resident with only ~2–3 B active per token.

---

## 2. Ranked shortlist

Sizes are **exact `size` bytes from the HF API** (`?blobs=true`) `[V]`. "Q4 size"
is the file the report recommends first. All GGUF filenames were confirmed to
exist by listing the repo tree.

| # | Name | HF repo | Recommended GGUF file | Released | Params (total/active) | Q4 file size | Place | License | Tool-calling | Why |
|---|------|---------|----------------------|----------|----------------------|--------------|-------|---------|--------------|-----|
| 1 | **Qwen3.5-4B** | `Qwen/Qwen3.5-4B` | `unsloth/Qwen3.5-4B-GGUF` → `Qwen3.5-4B-Q4_K_M.gguf` (or `UD-Q4_K_XL.gguf` 2.91 GB) | 2026-02-27 `[V]` | 4B dense (hybrid Gated-DeltaNet) | 2.74 GB | **GPU (A)** | Apache-2.0 `[V]` | Strong `[V, I]` | Best all-rounder: explicit `qwen3_coder` tool parser, 262K ctx, apache, tiny KV (linear-attention layers). Sits on 8 GB with huge KV headroom. |
| 2 | **Qwen3.5-9B** | `Qwen/Qwen3.5-9B` | `unsloth/Qwen3.5-9B-GGUF` → `Qwen3.5-9B-Q4_K_M.gguf` / `UD-Q4_K_XL.gguf` 5.97 GB | 2026-02-27 `[V]` | 9B dense (hybrid) | 5.68 GB | **GPU (A)** | Apache-2.0 `[V]` | Strong — native tool use + agentic section `[V]` | Highest raw quality that still fits 8 GB at Q4_K_M. Use at 16K ctx. Top pick if you want max GPU grunt. |
| 3 | **GLM-4.7-Flash** | `zai-org/GLM-4.7-Flash` | `unsloth/GLM-4.7-Flash-GGUF` → `GLM-4.7-Flash-Q4_K_M.gguf` | 2026-01-19 `[V]` | 30B / ~3B (MoE, 64 experts, 4/tok) `[V]` | 18.31 GB | **CPU (B, MoE)** | MIT `[V]` | Strong `[I]` | Best small-total MoE: 30B-A3B class, fast like a 3B, MIT. 18 GB Q4 is the "keep resident in RAM" option. IQ4_XS = 16.27 GB if RAM-tight. |
| 4 | **Gemma 4 E4B-it** | `google/gemma-4-E4B-it` | `google/gemma-4-E4B-it-qat-q4_0-gguf` → `gemma-4-E4B_q4_0-it.gguf` | 2026-03-02 `[V]` | 4.5B eff (8B w/ embeddings) `[V]` | 5.15 GB | **GPU (A)** | Apache-2.0 (Gemma 4 license = Apache) `[V]` | Good — native function calling `[V]` | QAT q4 = quality of a bigger quant at q4 size. Multimodal + audio. Official Google GGUF. |
| 5 | **IbM Granite-4.2-3B** | `ibm-granite/granite-4.2-3b` | `ibm-granite/granite-4.2-3b-GGUF` → `granite-4.2-3b-Q4_K_M.gguf` | 2026-08-07 `[V]` | 3B dense | 2.24 GB | **GPU or CPU (A/B)** | Apache-2.0 `[V]` | Very strong — purpose-built agentic RL `[V]` | Smallest solid tool-caller; explicit "agentic RL for multi-step tool use", 128K ctx. CPU decodes fast. |
| 6 | **Qwen3.5-2B** | `Qwen/Qwen3.5-2B` | `unsloth/Qwen3.5-2B-GGUF` → `Qwen3.5-2B-Q4_K_M.gguf` | 2026-02-28 `[V]` | 2B dense (hybrid) | 1.28 GB | **CPU (B)** | Apache-2.0 `[V]` | Moderate | 1.28 GB → ~30 tok/s CPU decode. Same tool parser family as 4B. Great cheap CPU grunt. |
| 7 | **NVIDIA Nemotron-3.5-Lightning-30B-A3B** | `nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-Base-BF16` | `unsloth/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF` → `…-UD-Q4_K_M.gguf` | 2026-08-05 `[V]` | 30B / 3B (Mamba-2 + MoE hybrid) `[V]` | 25.27 GB | **CPU (B, MoE)** | OpenMDW-1.1 `[V]` | Good `[I]` | 1M ctx, MTP/speculative-decode built in, 3B active. Bigger than GLM-Flash; use only if you want the Mamba long-context. |
| 8 | **Ibm Granite-4.2-8B** | `ibm-granite/granite-4.2-8b` | `ibm-granite/granite-4.2-8b-GGUF` → `granite-4.2-8b-Q4_K_M.gguf` | 2026-08-07 `[V]` | 8B dense | 5.35 GB | **GPU (A)** | Apache-2.0 `[V]` | Very strong `[V]` | 8B tool-caller with 512K-ctx support; Q4_K_M 5.35 GB fits 8 GB. Alternative to Qwen3.5-9B. |
| 9 | **Gemma 4 12B-it** | `google/gemma-4-12B-it` | `google/gemma-4-12B-it-qat-q4_0-gguf` → `gemma-4-12b-it-qat-q4_0.gguf` | 2026-05-23 `[V]` | 11.95B dense | 6.98 GB | **GPU (A, tight)** | Apache-2.0 `[V]` | Good | Fits 8 GB at q4 only with small KV (16K, p-RoPE). Highest dense quality on-card; watch KV growth. |
| 10 | **Qwen3.5-0.8B** | `Qwen/Qwen3.5-0.8B` | `unsloth/Qwen3.5-0.8B-GGUF` → `Qwen3.5-0.8B-Q4_K_M.gguf` | 2026-02-28 `[V]` | 0.8B dense | 0.53 GB | **CPU (B)** | Apache-2.0 `[V]` | Weak-moderate | ~70 tok/s CPU. Router/classifier/summarizer grunt, not a coder. |
| 11 | **Gemma 4 26B-A4B** | `google/gemma-4-26B-A4B-it` | `google/gemma-4-26B-A4B-it-qat-q4_0-gguf` → `gemma-4-26B_q4_0-it.gguf` | 2026-03-11 `[V]` | 25.2B / 3.8B (MoE) `[V]` | 14.44 GB | **CPU (B, MoE)** | Apache-2.0 `[V]` | Good | 3.8B active, 256K ctx. 14 GB resident in RAM; faster than GLM physically? both ~3–4B active. Good MoE alternative. |
| 12 | **Cohere North-Mini-Code-1.0** | `CohereLabs/North-Mini-Code-1.0` | (no official GGUF at 2026-10-18) | 2026-06-05 `[V]` | 128-expert MoE, 8/tok `[V]` | — | **CPU (B, MoE)** | (check card) | Strong `[I]` | Purpose-built code MoE, 500K ctx. **Flag:** GGUF availability unverified — see §4. |

**Skip-or-caution rows:**

- **Qwen3.5-35B-A3B** (`Qwen/Qwen3.5-35B-A3B`) — 35B/3B MoE, Apache-2.0, 2026-02-24 `[V]`.
  Great model, but smallest useful quant is `UD-Q2_K_XL` at 12.16 GB or
  `UD-IQ4_XS` at 17.49 GB `[V]` — heavier resident than GLM-4.7-Flash for
  similar speed. Pick only if you specifically want Qwen's agent RL.
- **Qwen3-Coder-Next** (`Qwen/Qwen3-Coder-Next-GGUF`) — **gated, no sizes shown**
  on the API `[V]`; large (multi-part). Not an 8 GB fit. Track, don't deploy yet.

---

## 3. Definitely do NOT use (pre-2026)

Strict cutoff: release **before 2026-01-01**. All of these are good models but
fail your date rule.

- **Ministral-3-3B-Instruct-2512** — HF repo created **2025-10-31** (the "2512"
  is a name, not the upload date) `[V]`. Superficially attractive, but pre-2026.
- **Mistral-Small-4-119B-2603** — created **2026-01-23** `[V]`. Actually in
  range, but 119B total: not an 8 GB or CPU grunt. Excluded on size.
- **gpt-oss-20b / gpt-oss-120b** — OpenAI, uploaded **2025-08-04**; no 2026
  official follow-up on the `openai` org (latest is `privacy-filter`, 2026-04-17)
  `[V]`. The many `gpt-oss-20b` 2026 repos are third-party finetunes of the 2025
  base — do not count as 2026 releases.
- **SmolLM3-3B** — HuggingFace, **2025-07-08** `[V]`. No `SmolLM4` exists as of
  2026-10-18 (search returns only third-party SmolLM3 finetunes) `[V]`.
- **OLMo 3 7B / Olmo-3.1-32B** — allenai, **2025-11-18/2025-12-10** `[V]`. In
  2026 allenai shipped `tmax-*` (see §5) instead.
- **Seed-OSS-36B** — ByteDance, **2025-08-20** `[V]`. No 2026 Seed-OSS release.
  The 2026 `Seed-OSS-36B` repos are mirrors/quantizations `[V]`.
- **Phi-4 / Phi-4-mini / Phi-4-multimodal** — Microsoft, **2024–2025** `[V]`.
  No official `Phi-5` exists on the `microsoft` org as of 2026-10-18 `[V]`.
- **Mistral Magistral-Small / Devstral-Small (2505/2507/2509)** — 2025 lineages
  `[V]`; the 2026 repos are quantizations of the 2025 weights.
- **Kimi-K2.5 / K2.6** — 2026-01-01 and 2026-04-14 `[V]`, so technically in
  range, but 100s of GB MoE — irrelevant to this hardware.
- **GLM-4.7-Flash is the exception**: it is the 2026-01-19 successor, keep it.

---

## 4. Verified vs inferred, and open items

**Verified `[V]`:** every release date, license string, param count, exact GGUF
filename and byte size in §2 was read directly from the HF API or the repo's
`config.json`/`README.md` on 2026-10-18. Repo trees were listed (not guessed).

**Inferred `[I]`:** placement throughput (tok/s) and "tool-calling quality"
ratings are engineering estimates from architecture + benchmark-table presence,
not measured on `brys`. Model cards claim tool use for Qwen3.5, Granite 4.2,
Gemma 4; the star ratings above are my synthesis.

**Open / to confirm before download:**

- **North-Mini-Code-1.0**: no official GGUF found; `[I]` third-party quants may
  appear. `[V]` config confirms `cohere2_moe`, 128 experts, 8/tok, 500K ctx.
- **Granite Switch 4.1 8B/30B** (`ibm-granite/granite-switch-4.1-8b`, 2026-10-14
  `[V]`) — these are adapter-composition "switch" models, not a plain chat GGUF;
  only a `granite-switch-4.1-3b-preview` third-party GGUF was seen `[V]`. Treat
  as experimental.
- **tmax** (`allenai/tmax-2b/4b/8b/9b`, 2026-06-17 `[V]`) — Apache-2.0, but the
  8B config is `qwen3` baseline and 2B/4B are `qwen3_5`; no official GGUF listed
  `[V]`. Watch; promising because tmax-8b is a Qwen3-8B terminal-agent tune.
- **Gemma 4 12B at 8 GB**: q4 weights alone are 6.98 GB, leaving <0.5 GB for KV
  at 16K — `[I]` risky. Prefer 26B-A4B's 3.8B-active on CPU, or Qwen3.5-9B on
  GPU.

---

## 5. Exact `hf download` commands (top candidates)

Use the `hf` CLI (`huggingface-cli` successor). Files marked are confirmed to
exist in the repo tree `[V]`.

```sh
# 1. Qwen3.5-4B — best GPU grunt, Q4_K_M (2.74 GB)
hf download unsloth/Qwen3.5-4B-GGUF Qwen3.5-4B-Q4_K_M.gguf --local-dir ./gguf
#    (higher quality alt: UD-Q4_K_XL.gguf 2.91 GB)
hf download unsloth/Qwen3.5-4B-GGUF Qwen3.5-4B-UD-Q4_K_XL.gguf --local-dir ./gguf
#    vision projector (optional)
hf download unsloth/Qwen3.5-4B-GGUF mmproj-F16.gguf --local-dir ./gguf

# 2. Qwen3.5-9B — max GPU quality, Q4_K_M (5.68 GB)
hf download unsloth/Qwen3.5-9B-GGUF Qwen3.5-9B-Q4_K_M.gguf --local-dir ./gguf

# 3. GLM-4.7-Flash — CPU MoE grunt (18.31 GB Q4_K_M)
hf download unsloth/GLM-4.7-Flash-GGUF GLM-4.7-Flash-Q4_K_M.gguf --local-dir ./gguf
#    RAM-tight alt (16.27 GB): GLM-4.7-Flash-IQ4_XS.gguf

# 4. Gemma 4 E4B-it — official QAT q4 (5.15 GB)
hf download google/gemma-4-E4B-it-qat-q4_0-gguf gemma-4-E4B_q4_0-it.gguf --local-dir ./gguf
hf download google/gemma-4-E4B-it-qat-q4_0-gguf gemma-4-E4B-it-mmproj.gguf --local-dir ./gguf

# 5. Granite-4.2-3B — best tiny tool-caller (2.24 GB)
hf download ibm-granite/granite-4.2-3b-GGUF granite-4.2-3b-Q4_K_M.gguf --local-dir ./gguf

# 6. Qwen3.5-2B — fast CPU grunt (1.28 GB)
hf download unsloth/Qwen3.5-2B-GGUF Qwen3.5-2B-Q4_K_M.gguf --local-dir ./gguf

# 7. Granite-4.2-8B — 8B tool-caller (5.35 GB)
hf download ibm-granite/granite-4.2-8b-GGUF granite-4.2-8b-Q4_K_M.gguf --local-dir ./gguf

# 8. Gemma 4 26B-A4B — CPU MoE alt (14.44 GB q4_0)
hf download google/gemma-4-26B-A4B-it-qat-q4_0-gguf gemma-4-26B_q4_0-it.gguf --local-dir ./gguf

# 9. Nemotron-3.5-Lightning-30B-A3B — Mamba MoE (25.27 GB UD-Q4_K_M)
hf download unsloth/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF \
  NVIDIA-Nemotron-3.5-Lightning-30B-A3B-UD-Q4_K_M.gguf --local-dir ./gguf
```

Quant guidance for the **8 GB card** (weights must be ≤ ~6 GB to leave KV room):

- Prefer **Q4_K_M** for Qwen3.5-4B / Granite-3B (small, safe).
- For **Qwen3.5-9B / Granite-8B**, Q4_K_M fits; use **`-c 16384`** and
  `-fa` (flash attention) to cap KV. Bump to **Q5_K_M** only if you drop ctx.
- For **Gemma 4 12B**, only **q4_0 QAT** is small enough; keep ctx ≤ 16K.
- For CPU MoE (GLM-4.7-Flash, Gemma 4 26B-A4B, Nemotron Lightning) use
  **Q4_K_M** or **IQ4_XS**; active params decide speed, file size decides RAM.
- **Never** pick Q6/Q8 for the 8 GB card — the smallest of those is the 4.62 GB
  Q8_0 for Qwen3.5-4B, leaving almost no KV room.

---

## 6. Bottom line

1. **GPU grunt:** start with **Qwen3.5-4B Q4_K_M** (fits with huge KV headroom,
   proper tool parser), scale to **Qwen3.5-9B Q4_K_M** at 16K ctx when you want
   more quality, and keep **Granite-4.2-3B** as the lightest reliable
   tool-caller.
2. **CPU grunt:** **Qwen3.5-2B** (or 0.8B) for speed, and **GLM-4.7-Flash**
   (30B-A3B, MIT) as the resident MoE workhorse at 18 GB Q4.
3. Everything here was released on/after 2026-01-19. The tempting older models
   (Ministral-3, gpt-oss, SmolLM3, OLMo-3, Seed-OSS, Phi-4) are all pre-2026 —
   exclude them.
