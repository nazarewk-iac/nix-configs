---
type: Research
description: Download and standalone measurement on brys of the remaining unmeasured popularity-sweep and specialized candidates (MiniCPM-V-4.7-1B, Ternary-Bonsai-2-27B, JiRackUltra-1B, JiRackDeltaNet-27B, Ornith-1.0-35B, Swift-1.5-Qwen3.8-27B-GSQ-RCO, Qwen3-Embedding-4B, Qwen3-Reranker-4B, parakeet-unified-en-0.6b, gemma-4-12b-it-qat). One-off llama-server, ctx 32768, -ngl 0, one row per model, modality and endpoint smoke tests, load and arch findings, disk notes.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T22:30:00+02:00
---

# Remaining unmeasured candidates on brys: download and measurement

This file records the download and the standalone measurement on host `brys`
only, for the candidates that [sweep.research.md](popularity-sweep/sweep.research.md)
named but that [popularity-sweep/measured.research.md](popularity-sweep/measured.research.md),
[new-candidates.research.md](new-candidates.research.md), and
[qwen-specialized-measured.research.md](qwen-specialized-measured.research.md) had
not measured. It does not register anything; registration is a separate
decision.

## Method

- One one-off `llama-server` per model on `127.0.0.1:39799`, one at a time,
  `--parallel 1`, `--no-warmup`, `-t 16`, `-fa on`, `-ngl 0`, `-c 32768`. Vision
  rows add `--mmproj <projector>`.
- Embedding rows add `--embedding --pooling last`. Reranker rows add `--rerank`.
- Build: the served `llama-cpp-sessions-vulkan-noblas` build 11539
  (`/nix/store/z77bfs2b63wfzlzfczcaq6apsigwd0qw-llama-cpp-sessions-vulkan-noblas-0.6.0-unstable-2026-10-09/bin/llama-server`).
  For the ternary model, the older vanilla `llama-cpp-0.6.0` build 11429 was
  also tried.
- `sync; echo 3 > /proc/sys/vm/drop_caches` before each load, so each `load_s`
  is a cold load.
- Decode: one short English prompt, 128-token cap. Prefill: one unique long
  prompt, 1-token cap; `prompt_n` is about 1030 in every row.
- Memory read from the real `llama-server` pid in `/proc/<pid>/status`. System
  `used` from `free -m` after the load. `RssFile` / `RssAnon` / `VmRSS` are shown
  in MiB.
- Download: `hf download` on brys with `HF_HUB_DISABLE_XET=1`, token at
  `/run/configs/llms/huggingface/token`, into
  `/var/lib/kdn/llms/models/surveyed/`. Each file was renamed to `<slug>.gguf`.
- Arch read from the GGUF metadata (`general.architecture`) with `strings`.
- Date: 2026-10-20. Box: Ryzen 5950X, 128 GB DDR4, one 8 GB AMD W6600.

## Downloads

| # | repo | file | size GB | local name | note |
|---|---|---|---|---|---|
| 1 | `openbmb/MiniCPM-V-4.7-1B-gguf` | `MiniCPM-V-4_7-1B-Q4_K_M.gguf` | 0.63 | `minicpm-v-4.7-1b.gguf` | + mmproj f16 1.03 GB |
| 2 | `prism-ml/Ternary-Bonsai-2-27B-gguf` | `Ternary-Bonsai-2-27B-PTQ1_0.gguf` | 5.54 | `ternary-bonsai-2-27b.gguf` | + mmproj BF16 0.87 GB |
| 3 | `CMSManhattan/JiRackUltra_1b` | `JiRackUltra_1b_Q4_K_M.gguf` | 1.04 | `jirackultra-1b.gguf` | text |
| 4 | `CMSManhattan/JiRackDeltaNet_27b` | `JiRackDeltaNet_27b.Q4_K_M.gguf` | 15.66 | `jirackdeltanet-27b.gguf` | text |
| 5 | `ornith-ai/Ornith-1.0-35B-GGUF` | `ornith-1.0-35b-Q4_K_M.gguf` | 19.71 | `ornith-1.0-35b.gguf` | text |
| 6 | `ukisai/Swift-1.5-Qwen3.8-27B-GSQ-RCO-GGUF` | `Swift-1.5-Qwen3.8-27B-GSQ-RCO-IQ3_S.gguf` | 10.96 | `swift-1.5-qwen3.8-27b-gsq-rco.gguf` | text |
| 7 | `Qwen/Qwen3-Embedding-4B-GGUF` | `Qwen3-Embedding-4B-Q4_K_M.gguf` | 2.33 | `qwen3-embedding-4b.gguf` | embedding |
| 8 | `Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp` | `Qwen3-Reranker-4B-Q4_K_M.gguf` | 2.33 | `qwen3-reranker-4b.gguf` | reranker |
| 9 | `handy-computer/parakeet-unified-en-0.6b-gguf` | `parakeet-unified-en-0.6b-Q4_K_M.gguf` | 0.44 | `parakeet-unified-en-0.6b.gguf` | ASR |
| 10 | `google/gemma-4-12B-it-qat-q4_0-gguf` | `gemma-4-12b-it-qat-q4_0.gguf` | 6.50 | `gemma-4-12b-it-qat-q4_0.gguf` | + mmproj 0.16 GB |

Sizes are GiB as written to disk (`stat` size / 1024^3), not decimal GB.

### Ternary-Bonsai file layout

The sweep says "mmproj only; weights separate". The repo holds both: the ternary
weights in two quants, `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (5.54 GiB) and
`Ternary-Bonsai-2-27B-PQ2_0.gguf` (6.71 GiB), plus two projectors. The F16
weights are 50.1 GiB and are out of scope. Both ternary quants were downloaded
and tried; both fail to load on build 11539 and on build 11429 (see the load
findings).

### A note on the download sizes

`hf download` reports decimal GB. This table uses GiB from `stat`, so the
numbers are smaller than the sweep figures. For example Ornith-1.0-35B is 21.17
decimal GB (sweep value) but 19.71 GiB on disk.

## Measurements

`ngl 0` for all rows (CPU only). Each throughput number is measured. Vision
rows that show a text value answered an image request; the empty cells are
explained in the notes. The gemma timing figures come from the text path; a
separate image request confirmed that its projector works.

| model | repo | file | size GB | arch | load_s | decode_tok_s | prefill_tok_s | RssFile/RssAnon/VmRSS MiB | SYS_MB | modality/endpoint smoke test | load OK? | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MiniCPM-V-4.7-1B | `openbmb/MiniCPM-V-4.7-1B-gguf` | Q4_K_M + mmproj f16 | 0.63 + 1.03 | `qwen35` | 3.1 | 51.78 | 759.9 | 662/667/1329 | 16637 | image FAIL; text OK | text only | projector type `minicpmv4_7` unsupported; see below |
| Ternary-Bonsai-2-27B | `prism-ml/Ternary-Bonsai-2-27B-gguf` | PTQ1_0 + mmproj BF16 | 5.54 + 0.87 | `qwen35` | — | — | — | — | — | — | **no** | ggml type 143 unknown to both builds |
| JiRackUltra-1B | `CMSManhattan/JiRackUltra_1b` | Q4_K_M | 1.04 | `qwen2` | 3.1 | 28.29 | 1307.6 | 1091/973/2065 | 17875 | text in `reasoning_content` | yes | thinking model; 1.78B |
| JiRackDeltaNet-27B | `CMSManhattan/JiRackDeltaNet_27b` | Q4_K_M | 15.66 | `qwen35` | 38.4 | 2.21 | 77.5 | 15802/3255/19058 | 22781 | text OK ("The sea breathes in and out...") | yes | very slow; dense-class decode |
| Ornith-1.0-35B | `ornith-ai/Ornith-1.0-35B-GGUF` | Q4_K_M | 19.71 | `qwen35moe` | 34.3 | 11.79 | 153.8 | 20208/1226/21434 | 20602 | text in `reasoning_content` | yes | superseded by 1.5-35B-A3B |
| Swift-1.5-Qwen3.8-27B-GSQ-RCO | `ukisai/Swift-1.5-Qwen3.8-27B-GSQ-RCO-GGUF` | IQ3_S | 10.96 | `qwen35` | 25.3 | 2.01 | 83.0 | 11251/3261/14512 | 23031 | text OK ("The sea stretches endlessly...") | yes | low-quant merge of Qwen3.8-27B |
| Qwen3-Embedding-4B | `Qwen/Qwen3-Embedding-4B-GGUF` | Q4_K_M | 2.33 | `qwen3` | 7.3 | n/a | n/a | 2406/4674/7081 | 22254 | `/v1/embeddings` OK, dim 2560, multi-input OK | yes | `--embedding --pooling last` |
| Qwen3-Reranker-4B | `Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp` | Q4_K_M | 2.33 | `qwen3` | 7.3 | n/a | n/a | 2407/4721/7129 | 23224 | `/v1/rerank` OK (0.867 vs 0.0001); `/v1/score` 404 | yes | `--rerank` |
| parakeet-unified-en-0.6b | `handy-computer/parakeet-unified-en-0.6b-gguf` | Q4_K_M | 0.44 | `parakeet` | — | — | — | — | — | — | **no** | unknown arch `parakeet` |
| gemma-4-12b-it-qat | `google/gemma-4-12B-it-qat-q4_0-gguf` | q4_0 + mmproj | 6.50 + 0.16 | `gemma4` | 15.2 | 3.54 | 157.3 | 6673/2096/8769 | 21543 | image OK ("The image contains a red circle."); text in `reasoning_content` | yes | QAT variant; thinking model |

Reference CPU values from the same class: `qwen3.8-27b` 2.45 decode / 78
prefill; `ornith-1.5-35b-a3b` 8.78 / 167; `north-mini-code-1.0` 18.0 / 178.

## Load and arch findings

### Two models do not load at all

**Ternary-Bonsai-2-27B** uses a ternary weight format that build 11539 does not
know. Both ternary quants fail at the GGUF parse stage, before any weight is
read:

```
gguf_init_from_reader: tensor 'output.weight' has invalid ggml type 143. should be in [0, 43)
llama_model_load: error loading model: llama_model_loader: failed to load model
```

The PQ2_0 quant fails the same way with type 142. The older vanilla
`llama-cpp-0.6.0` build 11429 (commit d812350) also rejects type 143. The valid
ggml type range in this build is `[0, 43)`; the ternary types 142 and 143 are
newer than the build. **Ternary-Bonsai cannot load on brys at the current
llama.cpp builds.** A newer llama.cpp that implements the ternary types is
required. The mmproj loads as a projector file in principle, but the base model
never reaches that step.

**parakeet-unified-en-0.6b** is an ASR model whose architecture llama.cpp does
not implement:

```
llama_model_load: error loading model: unknown model architecture: 'parakeet'
```

`llama-server` cannot serve Parakeet at all. Parakeet needs a dedicated ASR
runtime (for example `whisper.cpp`-style tooling or the NeMo stack), not
`llama-server`.

### The MiniCPM-V-4.7-1B projector is unsupported, the same as the 35B

The base model `qwen35` loads and answers text (51.78 tok/s decode, the fastest
of the set). The vision path fails at the projector load, exactly like the
MiniCPM-V-4.7-35B-A3B already recorded in
[popularity-sweep/measured.research.md](popularity-sweep/measured.research.md):

```
clip_init: failed to load model '.../mmproj-minicpm-v-4.7-1b.gguf':
load_hparams: unknown projector type: minicpmv4_7
```

So MiniCPM-V-4.7-1B runs text-only on brys. The projector type `minicpmv4_7` is
unknown to build 11539 (and to the 35B row's two builds). Vision needs a newer
llama.cpp.

### The small embedding and reranker models serve correctly

Both are `qwen3`-arch and load in about 7.3 s each. The embedding model returns
a 2560-dimension vector and accepts a batch of inputs. The reranker returns a
correct order through `/v1/rerank` (0.867 for the Paris document against 0.0001
for the Berlin document). The `/v1/score` endpoint is not present (404); only
`/v1/rerank` works. **llama-server serves both models.** They need the
`--embedding` / `--rerank` flags.

### Three thinking models answer in `reasoning_content`

Ornith-1.0-35B, JiRackUltra-1B, and gemma-4-12b-it-qat are reasoning models.
With a 128-token cap, the visible `content` field is empty and the answer sits
in `reasoning_content`. The decode speed is still measured correctly; only the
answer string moves. A caller must read `reasoning_content`, or raise the token
cap, or the reply looks empty.

### JiRackDeltaNet and Swift-1.5 decodes like dense 27B models

`qwen35` at 27B dense without an MoE path decodes at 2.21 tok/s (DeltaNet) and
2.01 tok/s (Swift), close to the served `qwen3.8-27b` (2.45). JiRackDeltaNet
also loads slowly (38.4 s) and has the largest footprint of the set (15.66 GiB
file, 18.6 GiB VmRSS). Swift-1.5 is an IQ3_S low-quant merge of Qwen3.8-27B, so
it is not a new base model.

### Ornith-1.0-35B is a slower sibling of Ornith-1.5-35B-A3B

Ornith-1.0-35B is `qwen35moe` and decodes at 11.79 tok/s, faster than Ornith-1.5-35B-A3B
in the earlier run (8.78). It is text-only (no projector in the repo) and the
sweep marks it superseded by 1.5. Measured for the record only.

## Skipped for disk

- **No candidate was skipped for disk in this run.** The free space at the
  start was 87 GiB, and the ten files above use about 70 GiB, leaving 17 GiB.
  The earlier run's Inkling-Small (about 158 GiB) remains the only disk skip and
  is not re-measured here.
- **Ternary-Bonsai F16** (50.1 GiB) and the `Ternary-Bonsai-2-27B-PQ2_0` quant
  (6.71 GiB) were not kept after the load test failed. The PQ2_0 file was
  removed to save space.

## Disk at the end

`/var/lib/kdn/llms/models` is on `brys-main/brys/impermanence/usr/data`:

```
1.4T  1.4T  17G  99%  /var/lib/kdn/llms/models
```

About 17 GiB free at the end of the run. The `llama-swap` service was not
stopped or restarted; `GET /v1/models` on `127.0.0.1:39700` still returns 34
ids.

## See also

- [popularity-sweep/sweep.research.md](popularity-sweep/sweep.research.md) —
  the desk sweep that named these candidates.
- [popularity-sweep/measured.research.md](popularity-sweep/measured.research.md)
  — the earlier brys run for the top-10 set; do not repeat.
- [new-candidates.research.md](new-candidates.research.md) — the mid-band set.
- [qwen-specialized-measured.research.md](qwen-specialized-measured.research.md)
  — the Qwen specialized set.
- [definition.md](definition.md) — this task.
- [hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix) — the
  registration point.
