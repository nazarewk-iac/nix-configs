---
type: Research
description: Multimodal small-model survey for a CPU + 8 GB-VRAM Vulkan host, by modality, from HF API on 2026-10-18.
task: definition.md
authored_by: agent
timestamp: 2026-10-18T06:00:00+02:00
---

# Multimodal small-model survey

Survey of 2026 small models that fit a host with a CPU fallback and one 8 GB-VRAM GPU via Vulkan.
Findings verified against the Hugging Face API on 2026-10-18.

> **VRAM-fit columns are inferred.** No fit was measured on the target host. Treat every `8GB?`
> value below as an estimate.

## Image / VLM

| Model | Params | License | Runtime | Released | 8GB? | Notes |
|---|---|---|---|---|---|---|
| Qwen3.5 small | 0.8B-9B | (per repo) | llama.cpp mtmd | 2026 | yes (≤~4B) | IS the VL line (`Qwen3_5ForConditionalGeneration` with `vision_config`); GGUFs ship `mmproj` |
| Gemma-4-E2B / E4B | 2B / 4B | Apache-2.0 | llama.cpp / official | 2026 | yes | 2026 small omni (vision + audio); official QAT GGUF |

## ASR

| Model | Params | License | Runtime | Released | 8GB? | Notes |
|---|---|---|---|---|---|---|
| Qwen3-ASR-0.6B / 1.7B | 0.6B / 1.7B | Apache-2.0 | llama.cpp (mmproj GGUF) | 2026-06-26 | yes | ships `mmproj` GGUF |
| Parakeet-TDT v3 | <1B | (per repo) | NeMo / GGUF | 2026 | yes | speed pick, <1 GB |
| Nemotron-3.5-ASR-Streaming-0.6B | 0.6B | (per repo) | GGUF | 2026-06-04 | yes | streaming |

## TTS

| Model | Params | License | Runtime | Released | 8GB? | Notes |
|---|---|---|---|---|---|---|
| Kokoro-82M | 82M | Apache-2.0 | ONNX / GGUF | 2025 | yes | tiny default |
| Qwen3-TTS | (per repo) | (per repo) | (per repo) | 2026 | inferred | |
| VibeVoice | (per repo) | (per repo) | (per repo) | 2026 | inferred | |
| IndexTTS-2.5 | (per repo) | (per repo) | (per repo) | 2026 | inferred | |
| MOSS-TTS | (per repo) | (per repo) | (per repo) | 2026 | inferred | |

## Embeddings

| Model | Params | License | Runtime | Released | 8GB? | Notes |
|---|---|---|---|---|---|---|
| Qwen3-Embedding-0.6B | 0.6B | Apache-2.0 | GGUF | 2025 | yes | best open GGUF |
| google/embeddinggemma-2 | (per repo) | (per repo) | (per repo) | 2026 | inferred | |
| Qwen3-VL-Embedding-2B | 2B | (per repo) | (per repo) | 2026 | inferred | |

## Code

| Line | Notes |
|---|---|
| Qwen2.5-Coder / Qwen3-Coder + LFM2.5 | Small code models |

> There is **no official Qwen3.5-Coder** as of 2026-10-18.

## Web agents

Qwen WebWorld-8B / 14B / 32B.

## Gaps

No 2026 small releases for Pixtral, Phi-mm, InternVL, SmolVLM, or XTTS. No Whisper successor.
