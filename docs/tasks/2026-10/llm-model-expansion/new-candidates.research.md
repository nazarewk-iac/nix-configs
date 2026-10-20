---
type: Research
description: Measured download and standalone profile of the five new mid-band and specialized model candidates on brys (one-off llama-cpp-sessions-vulkan-noblas, ctx 32768, -ngl 0); one row per model plus a best-candidate ranking.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T19:58:00+02:00
---

# New model candidates on brys: download and measurement

This file records the download and the standalone measurement on host `brys`
only, for the five new candidates of the mid-band and specialized surveys. It
does not register anything; registration is a separate decision.

## Method

- Build: the served `llama-cpp-sessions-vulkan-noblas`
  (`/nix/store/z77bfs2b63wfzlzfczcaq6apsigwd0qw-llama-cpp-sessions-vulkan-noblas-0.6.0-unstable-2026-10-09/bin/llama-server`).
- One one-off `llama-server` per model on `127.0.0.1:39799`, one at a time,
  `--parallel 1`, `--no-warmup`, `-t 16`, `--flash-attn on`, `-ngl 0`, `-c 32768`.
- `echo 3 > /proc/sys/vm/drop_caches` before each load, so each `load_s` is a
  cold load.
- Decode: one short English prompt, 128-token cap. Prefill: one unique prompt;
  `prompt_n` is reported in the table.
- Memory read from the real `llama-server` pid in `/proc/<pid>/status`. System
  `used` from `free -m` after the load.
- Date: 2026-10-20. Box: Ryzen 5950X, 128 GB DDR4, one 8 GB AMD W6600.
- Download: `hf download` on brys with `HF_HUB_DISABLE_XET=1`, token at
  `/run/configs/llms/huggingface/token`, into
  `/var/lib/kdn/llms/models/surveyed/`. Each file was renamed to
  `<slug>.gguf`. The sha256 of each file matches the Hugging Face LFS oid.

## Downloads

| # | repo | file | size GB | sha256 match | note |
|---|---|---|---|---|---|
| 1 | `LiquidAI/LFM2.5-24B-A2B-GGUF` | `LFM2.5-24B-A2B-Q4_K_M.gguf` | 14.53 | yes | new |
| 2 | `unsloth/Nemotron-3-Nano-30B-A3B-GGUF` | `Nemotron-3-Nano-30B-A3B-Q4_K_M.gguf` | 24.57 | yes | new |
| 3 | `ibm-granite/granite-switch-4.1-30b` | — | — | — | no GGUF exists; skipped |
| 4 | `unsloth/Olmo-3.1-32B-Think-GGUF` | `Olmo-3.1-32B-Think-Q4_K_M.gguf` | 19.48 | — | already present as `olmo-3.1-32b.gguf`; not re-measured |
| 5 | `NANI-Nithin/north-mini-code-gguf` | `North-Mini-Code-1.0-Q4_K_M.gguf` | 18.59 | yes | new |
| 6 | `Qwen/Qwen3-VL-8B-Instruct-GGUF` | `Qwen3VL-8B-Instruct-Q4_K_M.gguf` | 5.03 | yes | new |
| 6 | `Qwen/Qwen3-VL-8B-Instruct-GGUF` | `mmproj-Qwen3VL-8B-Instruct-F16.gguf` | 1.16 | yes | vision projector |

### Candidate 3: Granite-Switch-4.1-30B has no GGUF

The exact repo ids were verified on Hugging Face at 2026-10-20. There is **no
`ibm-granite/granite-switch-4.1-30b-GGUF`** (repository not found). A search for
`granite-switch` GGUF returns only `barha/granite-switch-4.1-3b-preview-GGUF`
(a 3B preview, below the band) and ONNX builds. There is no unsloth or bartowski
GGUF for the 30B. No official or community 30B GGUF exists, so the candidate is
skipped. The safetensors repo `ibm-granite/granite-switch-4.1-30b` exists.

### Candidate 4: Olmo-3.1-32B already present

`unsloth/Olmo-3.1-32B-Think-GGUF` -> `Olmo-3.1-32B-Think-Q4_K_M.gguf`
(19,482,034,816 bytes) was already downloaded on 2026-10-18 as
`olmo-3.1-32b.gguf` and is already served as the `olmo-3.1-32b` id. It was not
re-downloaded and not re-measured; the served suite covers it.

## Measurements

Measured on 2026-10-20. `ngl 0` for all rows (CPU only). Each throughput number
is measured. `RssFile` / `RssAnon` / `VmRSS` are KiB; the table shows MiB.

| model | repo | file | size GB | load_s | decode_tok_s | prefill_tok_s | RssFile_MiB | RssAnon_MiB | VmRSS_MiB | SYS_used_MB | load OK? | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| LFM2.5-24B-A2B | `LiquidAI/LFM2.5-24B-A2B-GGUF` | Q4_K_M | 14.53 | 22.4 | 22.3-24.1 | 276-287 | 13876 | 720 | 14597 | 19729 | yes | MoE, fast; two runs decode 24.1/22.3 |
| Nemotron-3-Nano-30B-A3B | `unsloth/Nemotron-3-Nano-30B-A3B-GGUF` | Q4_K_M | 24.57 | 36.6 | 12.1 | 186 | 23460 | 317 | 23777 | 19723 | yes | hybrid Mamba; largest RSS |
| North-Mini-Code-1.0 | `NANI-Nithin/north-mini-code-gguf` | Q4_K_M | 18.59 | 28.5 | 18.0 | 178 | 17753 | 1256 | 19010 | 20457 | yes | code specialist; MoE, fast |
| Qwen3-VL-8B-Instruct | `Qwen/Qwen3-VL-8B-Instruct-GGUF` | Q4_K_M + mmproj | 5.03 + 1.16 | 11.7 | 8.2-8.5 | 299-303 | 4821 | 4677 | 9498 | 22695 | yes | vision; image request OK ("Gradient") |
| Olmo-3.1-32B-Think | `unsloth/Olmo-3.1-32B-Think-GGUF` | Q4_K_M | 19.48 | — | — | — | — | — | — | — | (present) | already served; not re-measured |

`prompt_n` per row: LFM 1267, Nemotron 1280, North 1372, Qwen3-VL 1270.

Reference CPU values from the 27B doc: `qwen3.8-27b` 2.45 decode / 78 prefill;
`qwen3.6-27b` 3.13 / 102.

## Findings

### The MoE models decode far faster than the dense models

- **LFM2.5-24B-A2B** is the fastest new model: about 24 tok/s decode, about
  280 tok/s prefill. It is a MoE with about 2B active, so it reads few weights
  per token. The 14.53 GB file still fits the CPU easily (about 14.6 GiB VmRSS).
- **North-Mini-Code-1.0** decodes 18.0 tok/s (MoE, about 3B active). It is the
  best code specialist that fits, with good prefill (178 tok/s).
- **Nemotron-3-Nano-30B-A3B** decodes 12.1 tok/s. The hybrid Mamba stack keeps
  the decode near the predicted 13 tok/s. It has the largest RSS of the new set
  (23.8 GiB) because the Q4 file is 24.6 GB.

### The dense vision model is slow to decode but fast to prefill

- **Qwen3-VL-8B-Instruct** decodes only 8.2 tok/s despite the small size. This
  is unusual for an 8B dense model and points at a prefill-heavy or
  bandwidth-light decode path; prefill is high (300 tok/s). The mmproj loads
  and an image request answered ("Gradient"). The model and projector together
  use about 9.5 GiB VmRSS. The 8 GB W6600 could hold the 5.03 GB Q4 weights plus
  the 1.16 GB projector at partial offload, but this run is CPU-only by design.

### All loads succeeded

No load failure occurred for the four measured models. The Granite-Switch-4.1-30B
candidate was not measured because no GGUF exists.

### The swap server was left untouched

The one-off servers ran on port 39799. The `llama-swap` service was not stopped
or restarted, and `GET /v1/models` still returns 34 ids.

## Best new candidates

Ranking by measured speed, fit, and role:

1. **LFM2.5-24B-A2B** — fastest new model (24 tok/s decode, 280 prefill), MoE,
   14.53 GB, fits the CPU with the smallest footprint of the 20B+ set. Strong
   general grunt. LFM Open license. Worth registering.
2. **North-Mini-Code-1.0** — the one code specialist that fits (18 tok/s decode,
   178 prefill), 18.59 GB, Apache-2.0, tool use. Fills the code gap in the
   fleet. Worth registering.
3. **Qwen3-VL-8B-Instruct** — the vision candidate; the mmproj loads and image
   requests work, and it is tiny (5.03 GB + 1.16 GB) with 300 tok/s prefill. Low
   decode (8.2 tok/s) on the CPU, but this is the only VLM in the set. Worth
   registering for vision.
4. **Nemotron-3-Nano-30B-A3B** — a solid 12 tok/s MoE with a Mamba stack, but
   heavy (24.57 GB, 23.8 GiB RSS) and no clear advantage over the faster LFM.
   Optional; register only if a Mamba-class model is wanted.
5. **Olmo-3.1-32B-Think** — already present and served. No action.

### Worth registering

The top three: **LFM2.5-24B-A2B** (general, fastest), **North-Mini-Code-1.0**
(code specialist), and **Qwen3-VL-8B-Instruct** (vision). Nemotron is optional;
Granite-Switch is not possible.

## See also

- [mid-band-survey.research.md](mid-band-survey.research.md) — the desk survey
  that picked LFM2.5, Nemotron, Olmo, and Granite-Switch.
- [specialized-survey.research.md](specialized-survey.research.md) — the desk
  survey that picked North-Mini-Code and Qwen3-VL.
- [qwen3.8-27b.research.md](qwen3.8-27b.research.md) — the 27B method reused
  here.
- [definition.md](definition.md) — this task.
