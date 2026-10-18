---
type: Research
description: Free, self-hostable end-to-end pipeline for locating key moments in long recordings, with per-stage model picks.
task: definition.md
authored_by: agent
timestamp: 2026-10-18T06:00:00+02:00
---

# Media moments — key-moment pipeline

An end-to-end pipeline for locating key moments in long recordings. All stages are free and
self-hostable.

> **No single 2026 model does this.** The architecture is **fusion** of independent signals.

## Stages

0. **ffmpeg demux** — 16 kHz WAV + video; `silencedetect`/`blackdetect`.
1. **ASR** — whisper.cpp large-v3 (ggml, Vulkan/CPU, word timestamps `-ml 1`, Silero VAD);
   optional WhisperX `--device cpu --compute_type int8` (word alignment + pyannote diarization);
   optional Parakeet-TDT-0.6B-v3 GGUF for long-form.
2. **Audio events** — PANNs Cnn14_DecisionLevelMax frame-wise SED (2 s hop), PaSST
   `get_timestamp_embeddings`, CLAP zero-shot labels.
3. **Scene cuts** — PySceneDetect `ContentDetector` (v0.7.2, 2026-10-11).
4. **Visual pass** — sample frames → Qwen3-VL-8B GGUF Q4 on llama.cpp-Vulkan, prompt for
   `[start,end]`; or InternVideo3-8B agent loop.
5. **Index/search** — SigLIP2 frame embeddings + CLAP audio embeddings → FAISS/sqlite-vec;
   query "show me the part where ...".
6. **Highlights** — Moment-DETR / QVHighlights → ranked `[start, end, saliency]`.
7. **Fusion** — weighted vote → EDL/CSV, SRT, chapters, ffmpeg highlight clips.

### Fusion weight formula

```
score = w1 * ASR-keyword-match
      + w2 * audio-event-novelty
      + w3 * scene-boundary-proximity
      + w4 * VLM-confidence
      + w5 * Moment-DETR-saliency
```

## Per-stage candidate table

| Stage | Name | URL | Modality | Params | License | Runtime | Released | 8GB? | Long? |
|---|---|---|---|---|---|---|---|---|---|
| 0 | ffmpeg | ffmpeg.org | audio+video | n/a | LGPL/GPL | native | ongoing | n/a | yes |
| 1 | whisper.cpp large-v3 | github.com/ggerganov/whisper.cpp | audio | 1.5B | MIT | ggml (Vulkan/CPU) | 2023 | yes (GPU/CPU) | via VAD |
| 1 | WhisperX | github.com/m-bain/whisperX | audio | (2 models) | BSD | Python (CPU int8) | 2023 | yes | yes |
| 1 | Parakeet-TDT-0.6B-v3 | HF | audio | 0.6B | (per repo) | GGUF | 2026 | yes | yes |
| 2 | PANNs Cnn14_DecisionLevelMax | github.com/qiuqiangkong/audioset_tagging_cnn | audio | 80M | MIT | PyTorch | 2020 | yes | frame-wise |
| 2 | PaSST | github.com/kkoutini/PaSST | audio | ~87M | (per repo) | PyTorch | 2022 | yes | embeddings |
| 2 | CLAP | github.com/LAION-AI/CLAP | audio+text | (per repo) | (per repo) | PyTorch | 2023 | yes | zero-shot |
| 3 | PySceneDetect ContentDetector | scenedetect.com | video | n/a | BSD-3 | Python/OpenCV | v0.7.2 2026-10-11 | n/a | yes |
| 4 | Qwen3-VL-8B GGUF Q4 | HF | image+text | 8B | (per repo) | llama.cpp-Vulkan | 2026 | marginal (Q4) | sampled |
| 4 | InternVideo3-8B | HF | video+text | 8B | (per repo) | (per repo) | 2026 | inferred no | agent loop |
| 5 | SigLIP2 | HF | image+text | (per repo) | Apache-2.0 | PyTorch/ONNX | 2024 | yes | per-frame |
| 6 | Moment-DETR / QVHighlights | github.com/jayleicn/moment_detr | video+text | (per repo) | (per repo) | PyTorch | 2021 | inferred | ranked spans |

**Verified** against the HF API / repo listing on 2026-10-18 unless the cell says `inferred`,
`per repo`, or `yes (GPU/CPU)`. Every `8GB?` and `Long?` value is an inference, not a measurement.
