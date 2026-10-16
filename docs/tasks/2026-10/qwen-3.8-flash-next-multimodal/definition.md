---
type: Task
description: Serve Qwen3.8-Flash-Next with its multimodal projector on the main brys profile behind a toggle, so llama-server accepts image and video input, not text alone.
status: in-progress
authored_by: agent
timestamp: 2026-10-16T08:11:54+02:00
---

# Qwen3.8-Flash-Next multimodal (vision) serving on brys

## Context

`Qwen/Qwen3.8-Flash-Next` is an **`image-text-to-text`** model: it has a vision
encoder and it handles images and video, not text alone. The deployed brys
entries serve it **text-only**, because the LLM router loads no multimodal
projector.

The model is served by the den `llm` aspect
([modules/den/aspects/llm.nix](../../../modules/den/aspects/llm.nix)) as a
`llama-server` router. A vision-capable GGUF needs a **separate projector file**
(`mmproj-F16.gguf`, ~0.8 GB on the Unsloth repo) passed to llama-server as
`--mmproj`. Without it llama-server rejects image and video input, so the model
answers text only — even though the weights support vision.

The gap was recorded, not overlooked:
[docs/tasks/2026-10/qwen-flash-next-quant/definition.md](../qwen-flash-next-quant/definition.md)
lines 48 and 152-153 name the model as multimodal and park the projector as a
follow-up ("the slot has no `mmproj` option today"). This task is that follow-up.

## Goal

1. Add an `mmproj` option to the model submodule of the `llm` aspect, so any
   model can declare a vision projector (download + `--mmproj` preset key).
2. Fold vision into the **main `brys` profile** behind a single toggle
   (`qwenVision` in `hosts/brys/llm.nix`), so the operator flips one switch to
   turn image and video input on or off. No separate boot specialisation.
3. (Later) cold-boot it, verify image and video input over the LAN endpoint, and
   measure the added cost.

## Baseline

Vision is the existing main-profile Qwen config plus one switch. The baseline it
copies:

- Qwen3.8-Flash-Next `UD-IQ4_XS`, 3 shards, ~94 GB, n-gram table inside the weights.
- Context 1048576 (1M), YaRN x4 (`rope-scale` 4.0, `rope-freq-base` 10000000,
  `yarn-orig-ctx` 262144), `q8_0` KV, `batch`/`ubatch` 4096.
- `parallel 4` with unified KV, threads 16, flash-attn on, reasoning auto.
- MTP speculative decode **off**, W6600 **unused**.

See [docs/local-llms.md](../../../docs/local-llms.md) for the measured deployment
and every tuning lever.

## Proposed approach

1. **Aspect option** (done). The `llm` aspect gains `models.<name>.mmproj.{enable,hfRepo,hfFile}`,
   an `mmprojFile` path helper, an `mmproj = <path>` preset key, and a download step
   that runs before the parent model (the same shape as `draft`).
2. **Host toggle** (done). `hosts/brys/llm.nix` gains a `qwenVision` argument
   (default false) that adds the `mmproj-F16.gguf` entry to the Qwen model. Every
   consumer that omits it stays text-only and byte-identical.
3. **Main profile on** (done). `hosts/brys/default.nix` sets `qwenVision = true`,
   so the main `brys` entry serves image and video input. Flip it to false to go
   back to text-only. The projector downloads when the model downloads.
4. **Cold-boot and measure** (not done — the change lands on the next switch or
   reboot of the main profile).

The dedicated `llm-qwen` and `llms-frontier` boot entries keep `qwenVision` at its
false default; they serve Qwen text-only. Set it true there too if vision is
wanted on a frontier boot entry.

## Tuning levers to test (later)

- **Video frame rate**: the model card recommends raising `longest_edge` in
  `video_preprocessor_config.json` to 469,762,048 (224k video tokens) for
  hour-scale video. Whether llama.cpp exposes this as a server flag is unknown —
  verify before claiming long-video support.
- **Vision prefill cost**: the vision encoder adds prefill work on the CPU-only
  box. Measure the added latency on an image prompt against the text baseline.
- **Projector quant**: `mmproj-F16.gguf` (~0.8 GB) is the default; a lower-bit
  projector (`mmproj` in another quant) may cut RAM at some quality cost.
- **API shape**: the client sends images as OpenAI `image_url` content parts
  (confirmed in the model card's example). Confirm the compat proxy
  ([modules/den/aspects/llm.nix](../../../modules/den/aspects/llm.nix)) passes the
  content array through unchanged.

## Acceptance criteria

- The `llm` aspect evaluates with the new `mmproj` option on every existing host
  (no behaviour change when unset).
- The main `brys` profile evaluates with `qwenVision = true`, and the rendered
  preset INI carries the `mmproj` key.
- (Later) an image prompt and a video prompt answered over the LAN endpoint.
- (Later) the projector's RAM and the vision prefill cost are recorded in
  [docs/local-llms.md](../../../docs/local-llms.md).

## Open questions

- Does the pinned `llama-cpp-sessions` build (`packages/llama-cpp`) accept
  `--mmproj` for the `qwen4exp` architecture? The projector is a standard
  `clip`/`mtmd` projector, but verify at load.
- Does the router preset INI accept `mmproj` as a per-model key (the router
  expands it onto the child process)? Verify against the v0.6.0 router.
- Does the QSA hybrid attention path coexist with the vision encoder at 1M
  context, or does the vision tower cap the usable context?

## References

- [hosts/brys/llm.nix](../../../../hosts/brys/llm.nix) — the shared Qwen wiring;
  the new `qwenVision` toggle.
- [hosts/brys/default.nix](../../../../hosts/brys/default.nix) — the main profile;
  sets `qwenVision = true`.
- [hosts/brys/llm-qwen.nix](../../../../hosts/brys/llm-qwen.nix) — a text-only
  baseline entry (`qwenVision` default).
- [modules/den/aspects/llm.nix](../../../../modules/den/aspects/llm.nix) — the
  aspect; the new `mmproj` option, preset key and download step.
- [docs/local-llms.md](../../../docs/local-llms.md) — the deployment, tuning and
  benchmark log.
- HuggingFace `unsloth/Qwen3.8-Flash-Next-GGUF` — the `mmproj-F16.gguf` projector
  and the vision benchmark table.
