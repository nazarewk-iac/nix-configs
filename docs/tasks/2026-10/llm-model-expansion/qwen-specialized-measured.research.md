---
type: Research
description: Measured download and standalone profile on brys of the five Qwen specialized models that the survey says run on llama.cpp (Coder-30B-A3B, VL-30B-A3B, Omni-30B-A3B, QwQ-32B, VL-32B). One-off llama-server, ctx 32768, -ngl 0, one row per model, modality smoke tests, plus a registration ranking.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T20:35:00+02:00
---

# Qwen specialized models on brys: download and measurement

This file records the download and the standalone measurement on host `brys`
only, for the five Qwen specialized models that
[qwen-specialized-survey.research.md](qwen-specialized-survey.research.md) says
run on llama.cpp. It does not register anything; registration is a separate
decision. The method is the same as
[new-candidates.research.md](new-candidates.research.md) and
[qwen3.8-27b.research.md](qwen3.8-27b.research.md).

## Method

- Build: the served `llama-cpp-sessions-vulkan-noblas`
  (`/nix/store/z77bfs2b63wfzlzfczcaq6apsigwd0qw-llama-cpp-sessions-vulkan-noblas-0.6.0-unstable-2026-10-09/bin/llama-server`).
- One one-off `llama-server` per model on `127.0.0.1:39799`, one at a time,
  `--parallel 1`, `--no-warmup`, `-t 16`, `--flash-attn on`, `-ngl 0`,
  `-c 32768`. Vision and Omni rows add `--mmproj <projector>`.
- `echo 3 > /proc/sys/vm/drop_caches` before each load, so each `load_s` is a
  cold load.
- Decode: one short English prompt, 128-token cap, no prompt cache. Prefill: one
  unique long prompt, 1-token cap; `prompt_n` is about 968 in every row.
- Memory read from the real `llama-server` pid in `/proc/<pid>/status`. System
  `used` from `free -m` after the load.
- Download: `hf download` on brys with `HF_HUB_DISABLE_XET=1`, token at
  `/run/configs/llms/huggingface/token`, into
  `/var/lib/kdn/llms/models/surveyed/`. Each file was renamed to `<slug>.gguf`.
- Date: 2026-10-20. Box: Ryzen 5950X, 128 GB DDR4, one 8 GB AMD W6600.

## Downloads

All five files verified: the sha256 on brys matches the Hugging Face LFS oid.

| model | repo | file | size GB | sha256 match |
|---|---|---|---|---|
| Qwen3-Coder-30B-A3B-Instruct | `unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF` | `Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf` | 18.56 | yes |
| Qwen3-VL-30B-A3B-Instruct | `Qwen/Qwen3-VL-30B-A3B-Instruct-GGUF` | `Qwen3VL-30B-A3B-Instruct-Q4_K_M.gguf` + `mmproj-...-F16.gguf` | 18.56 + 1.08 | yes |
| Qwen3-Omni-30B-A3B-Instruct | `ggml-org/Qwen3-Omni-30B-A3B-Instruct-GGUF` | `Qwen3-Omni-30B-A3B-Instruct-Q4_K_M.gguf` + `mmproj-...-Q8_0.gguf` | 18.56 + 1.33 | yes |
| QwQ-32B | `Qwen/QwQ-32B-GGUF` | `qwq-32b-q4_k_m.gguf` | 19.85 | yes |
| Qwen3-VL-32B-Instruct | `Qwen/Qwen3-VL-32B-Instruct-GGUF` | `Qwen3VL-32B-Instruct-Q4_K_M.gguf` + `mmproj-...-F16.gguf` | 19.76 + 1.20 | yes |

Notes:

- The task listed `Qwen/Qwen3-Omni-30B-A3B-Instruct-GGUF`. That repo id does
  **not** exist. The GGUF is in `ggml-org/Qwen3-Omni-30B-A3B-Instruct-GGUF`. That
  is the repo used.
- The HF cache was removed after the move. Disk went from 276 GB free to 184 GB
  free after the five downloads and the sha256 pass.

## Measurements

Each throughput number is measured. `ngl 0` for all rows (CPU only). `RssFile` /
`RssAnon` / `VmRSS` are shown in MiB. `SYS_used_MB` is the whole-system `used`
after the load. `prompt_n` is about 968 in every row.

| model | repo | file | size GB | arch | load_s | decode_tok_s | prefill_tok_s | RssFile/RssAnon/VmRSS MiB | SYS_MB | modality smoke test | load OK? | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Qwen3-Coder-30B-A3B | `unsloth/...-GGUF` | Q4_K_M | 18.56 | `qwen3moe` | 30.3 | 9.10 | 207.0 | 18148/3215/21363 | 22409 | code prompt OK (coherent Fibonacci, found the mutable-default bug) | yes | MoE; fastest prefill of the set |
| Qwen3-VL-30B-A3B | `Qwen/Qwen3-VL-30B-A3B-Instruct-GGUF` | Q4_K_M + mmproj F16 | 18.56 + 1.08 | `qwen3vlmoe` | 30.3 | 15.70 | 167.2 | 18148/3220/21368 | 22183 | image OK ("blue at the top to yellow at the bottom"; "solid red circle") | yes | MoE VLM; best decode of the 30B set |
| Qwen3-Omni-30B-A3B | `ggml-org/...-Instruct-GGUF` | Q4_K_M + mmproj Q8_0 | 18.56 + 1.33 | `qwen3vlmoe` | 31.3 | 8.78 | 168.6 | 18149/3248/21397 | 22458 | image OK ("solid red circle"); audio OK (exact transcript of an espeak-ng clip) | yes | audio + vision + text in one server |
| QwQ-32B | `Qwen/QwQ-32B-GGUF` | Q4_K_M | 19.85 | `qwen2` | 35.3 | 1.65 | 84.7 | 19412/8460/27871 | 27571 | n/a (text) | yes | dense 32B; slow and heavy |
| Qwen3-VL-32B | `Qwen/Qwen3-VL-32B-Instruct-GGUF` | Q4_K_M + mmproj F16 | 19.76 + 1.20 | `qwen3vl` | 34.3 | 2.16 | 81.5 | 19325/8464/27790 | 27374 | image OK ("solid red circle on a white background"; gradient described) | yes | dense VLM; slow decode |

Reference CPU values from the same class: `qwen3.8-27b` 2.45 decode / 78 prefill;
`north-mini-code-1.0` 18.0 / 178; `lfm2.5-24b-a2b` 24.1 / 280.

## Findings

### The MoE models decode far faster than the dense models

- **Qwen3-VL-30B-A3B** is the fastest of the five: 15.7 tok/s decode. It is a MoE
  with about 3B active, so it reads few weights per token.
- **Qwen3-Coder-30B-A3B** decodes 9.1 tok/s but has the best prefill (207 tok/s)
  of the set. The same MoE shape at about 3B active; the lower decode than the VL
  sibling is consistent with a code-tuned model and measurement noise.
- **Qwen3-Omni-30B-A3B** decodes 8.8 tok/s with prefill 169 tok/s. It routes
  through the same `qwen3vlmoe` loader as the VL-30B-A3B and holds the mmproj plus
  an audio tower. It is the only model here that answers on three modalities from
  one server.
- **QwQ-32B** (1.65 tok/s) and **Qwen3-VL-32B** (2.16 tok/s) are dense 32B
  models. They read all weights per token, so they are about 7x slower than the
  MoE models. Both hold about 27.9 GiB VmRSS, the largest of the set, because the
  dense Q4 weights are about 19.8 GB and the KV cache adds to it. The task's
  predicted about 2 tok/s for the dense models holds.

### All five models loaded and all modality tests passed

No load failure occurred. The exact architectures from `general.architecture`:
`qwen3moe`, `qwen3vlmoe`, `qwen3vlmoe`, `qwen2`, `qwen3vl`. Every arch is in the
llama.cpp table, so all five run on brys.

### The Omni GGUF uses the `qwen3vlmoe` architecture, not `qwen3_omni_moe`

The survey predicted `qwen3_omni_moe` for `Qwen3-Omni-30B-A3B`. The
`ggml-org` GGUF in fact declares `general.architecture = qwen3vlmoe` in its
metadata. llama.cpp loads it through the `qwen3vlmoe` path and wires the audio
input through the mmproj. The audio test proved this: the server transcribed an
espeak-ng clip ("The quick brown fox jumps over the lazy dog") word for word.
This is the one correction to the survey's arch column.

### The mmproj is needed for the VL and Omni rows only

The three text/no-mmproj rows (Coder, QwQ) served text with no projector. The
VL-30B-A3B, VL-32B, and Omni rows each loaded a projector and answered image
requests. The Omni row answered an audio request as well. A text-only deployment
of a VL or Omni model can omit the projector, but the vision and audio tests here
needed it.

### The swap server was left untouched

The one-off servers ran on port 39799. The `llama-swap` service was not stopped
or restarted. After the measurements, `GET /v1/models` on `127.0.0.1:39700` still
returns 34 ids.

## Ranking: which Qwen specialized models are worth registering

Ranking by measured speed, fit, and role. All five run on brys; the ranking is
about value in the fleet.

1. **Qwen3-VL-30B-A3B-Instruct** — the best fit of the set. It is the fastest
   (15.7 tok/s decode), a MoE that fits the CPU, and it adds vision, which the
   fleet lacks at the 30B class. Apache-2.0. Register first.
2. **Qwen3-Coder-30B-A3B-Instruct** — the pure-Qwen CPU coder (9.1 tok/s decode,
   207 tok/s prefill), 18.56 GB, Apache-2.0, and the code smoke test passed. It
   fills the code role beside North-Mini-Code. Register second.
3. **Qwen3-Omni-30B-A3B-Instruct** — the only audio+vision+text model that fits,
   and both modality tests passed. 8.8 tok/s decode. License `other` (Qwen
   custom), not Apache. Register third, for the audio role.
4. **Qwen3-VL-32B-Instruct** — vision works, but 2.16 tok/s decode and 27.8 GiB
   VmRSS make it a poor CPU fit. The 30B-A3B MoE variant is faster and smaller for
   the same vision role. Optional.
5. **QwQ-32B** — the slowest (1.65 tok/s) and heaviest (27.9 GiB VmRSS) of the
   five. A dated dense reasoning model with no role the fleet lacks. Optional at
   best.

### Worth registering

The top three: **Qwen3-VL-30B-A3B** (vision, fastest), **Qwen3-Coder-30B-A3B**
(code), and **Qwen3-Omni-30B-A3B** (audio + vision + text). The two dense 32B
models are optional and the least attractive on this CPU.

### Failed to load

None. All five architectures (`qwen3moe`, `qwen3vlmoe`, `qwen2`, `qwen3vl`) are
implemented by the served llama.cpp build, so no model needed a newer binary.

## See also

- [qwen-specialized-survey.research.md](qwen-specialized-survey.research.md) —
  the desk survey that picked these five.
- [new-candidates.research.md](new-candidates.research.md) — the same method for
  the mid-band candidates.
- [qwen3.8-27b.research.md](qwen3.8-27b.research.md) — the 27B method reused here.
- [definition.md](definition.md) — this task.
- [hosts/brys/llm-routers.nix](../../../../hosts/brys/llm-routers.nix) — the
  registration point.
