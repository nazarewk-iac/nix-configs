---
type: Measurement
description: Timed runs of the candidate image and video editors on the single R9700, through stable-diffusion.cpp on Vulkan, at both the production power cap and the card's ceiling.
authored_by: agent
timestamp: 2026-11-20T17:45:00+01:00
---

# Editor survey on brys

Host `brys`: one Radeon AI PRO R9700 (gfx1201, 31.86 GiB), 5950X, 125 GiB RAM, no swap. Serving
stack: `stable-diffusion.cpp` built with `vulkanSupport = true`
(`nixpkgs#stable-diffusion-cpp.override { vulkanSupport = true; }`), upstream `master-532d2c1`,
no torch and no ROCm.

Every run uses the same prompt and the same reference image: a 1024x1024 photograph of a wooden dock
on a lake, instruction *"turn the sky into a dramatic orange sunset with heavy clouds"*. Seed 42,
Euler, flow shift 3.

## Power: both numbers, on purpose

The fleet caps the card at **210 W** (`hosts-den/brys/gpu-power.nix`), which is the VBIOS floor —
the lowest value the SMU accepts. That is the production setting, and it is what the daily numbers
come from.

A benchmark has the opposite requirement: it should not be limited by our electricity policy, or the
next card's numbers are not comparable. So the survey was run twice, once at 210 W and once at the
card's factory **300 W** ceiling, and both are reported. The cap costs **3-10 %** of wall time:

| run | 210 W | 300 W | difference |
| --- | --- | --- | --- |
| Qwen-Image-Edit + Lightning, 4 steps | 44 s | 41 s | +7 % |
| LongCat-Image-Edit-Turbo, 8 steps | 30 s | 29 s | +3 % |
| Qwen-Image-Edit, 20 steps | 293 s | 266 s | +10 % |
| Wan2.1 VACE 14B, 20 steps | 1039 s | 940 s | +10 % |

That matches the earlier frontier measurement: a board cap mostly costs prefill and the long
denoise, and it buys 90 W of heat and noise back. The cap stays at 210 W; the 300 W column is the
objective figure.

## Trap 1: the RX 550 enumerates first

`sd-cli` sees two Vulkan devices on this host:

```
ggml_vulkan: 0 = AMD Radeon RX 550 / 550 Series (RADV POLARIS12) | fp16: 0 | bf16: 0
ggml_vulkan: 1 = AMD Radeon AI PRO R9700 (RADV GFX1201)     | fp16: dot2 | bf16: 1 | KHR_coopmat
```

`--backend vulkan0` therefore means *the 4 GB Polaris card*, not the R9700. The first run did
exactly that: **147 s/it** and 3.7 GB resident on the RX 550. Every number below pins
`diffusion=vulkan1,te=vulkan1,vae=vulkan1`. `GGML_VK_VISIBLE_DEVICES=1` gives the same result and
is what the serving unit should set, because the order depends on PCI enumeration.

## Trap 2: a GGUF conversion can be silently wrong

`vantagewithai/LongCat-Image-Edit-Turbo-GGUF` (Q8_0) loads without a single missing tensor, is
detected as `Longcat-Image`, and produces **noise**: the composition is faintly there (the red
square of the test card is where it belongs) but the image is unusable. The same prompt and the
same VAE with the official `Comfy-Org` bf16 safetensors produce a correct image. The conversion,
not the runtime, is at fault. LongCat needs the BFL-format conversion, and that repo does not do
it.

**Rule: a new diffusion model is proven with the official single-file weights before any GGUF of
it is trusted.**

## Image editors

1024x1024 unless noted. Peak VRAM includes the shared Qwen2.5-VL-7B Q8_0 encoder (8.1 GB) and its
`mmproj-F16` (1.35 GB), which both image editors load.

| model | weights | size | steps | cfg | 210 W | 300 W | peak VRAM |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Qwen-Image-Edit-2511 + Lightning 4-step LoRA** | Q4_K_M + 850 MB LoRA | 13.6 GB | 4 | 1.0 | 44 s | **41 s** | 26.2 GiB |
| Qwen-Image-Edit-2511 | Q4_K_M GGUF | 12.8 GB | 20 | 2.5 | 293 s | 266 s | 25.4 GiB |
| **LongCat-Image-Edit-Turbo** | official bf16 safetensors | 12.5 GB | 8 | 1.0 | 30 s | **29 s** | 22.9 GiB |
| LongCat-Image-Edit-Turbo | Q8_0 GGUF (third-party) | 6.3 GB | 8 | 1.0 | 25 s | — | 17.4 GiB |
| Qwen-Image-Edit-2511 | Q4_K_M GGUF, 512x512 | 12.8 GB | 20 | 2.5 | 66 s | — | 20.8 GiB |

Per-step cost at 1024x1024: **14.1 s/step** for Qwen-Image-Edit (20B), **2.0 s/step** for
LongCat-Turbo (6B). That ratio, not the benchmark table, is what a person feels. The Lightning LoRA
turns 20 steps into 4 at the same per-step cost, which is where the 7x comes from.

The broken GGUF is listed deliberately: it is 25 s of wall time and 17.4 GiB for an unusable image,
and it is the reason the entry in `data/llm.nix` names the official Comfy-Org file.

### Quality, read off the same photo

- **Qwen-Image-Edit-2511, 20 steps**: the sky becomes a full sunset with layered clouds, the
  water picks up an orange reflection, the dock and the railings stay pixel-faithful. No visible
  seam at the horizon.
- **Qwen-Image-Edit-2511, Lightning 4 steps**: the same edit at a seventh of the time, slightly
  flatter clouds and a more uniform reflection. For a batch job that is the right trade.
- **LongCat-Image-Edit-Turbo, 8 steps**: a more restrained sunset — darker, more realistic clouds,
  a subtler reflection. Not worse, just less dramatic; it follows the instruction literally and
  keeps the photograph's own colour grading.
- **The broken LongCat GGUF**: uniform high-frequency noise over a faintly visible layout.

## Video: Wan2.1 VACE 14B

Q4_K_M GGUF (11.6 GB), umt5-xxl Q8_0 encoder (6.0 GB), Wan 2.1 VAE. 832x480, 33 frames (2 s at
16 fps), 20 steps, cfg 6.0, reference-to-video from the same photograph.

| 210 W | 300 W | peak VRAM | per step |
| --- | --- | --- | --- |
| 1039 s (17m19s) | **940 s (15m40s)** | 28.6 GiB | 45-50 s |

The clip is valid and the motion is real — the water ripples evolve between frames while the dock
stays fixed — but a reference-to-video run *animates* the photograph, it does not restyle it: the
sunset of the image prompt does not appear. The instruction-editing modes (masked replacement,
subject swap, outpainting) are the VACE video-to-video paths with a control video, which this
survey did not exercise. Treat the number as "the video path works and costs a quarter of an hour
per two seconds at 20 steps", not as an editing benchmark.

## What the numbers mean for the fleet

- An edit at 1024x1024 costs **30-45 s** with a distilled model and **4.5 min** with the 20B at 20
  steps. That is a batch job, which is why the entry belongs in the `main` set and evicts `qfn`.
- Peak VRAM is **23-26 GiB** for an image edit and **28.6 GiB** for a 2 s video. Nothing here fits
  beside `qfn-max` (~30 GB), and nothing fits beside `qfn-colo` *plus* the omni companion
  (~30.5 GB). The exclusive-mode decision stands.
- The 4 GB RX 550 is a hazard, not a resource: pin the device or the job runs 100x slower while
  looking like it works.
- A video job is 20x an image job. It belongs behind the same exclusive switch, with a queue and a
  timeout, not behind a chat alias.

## Reproduce

```sh
# build (Vulkan, no torch, no ROCm)
nix build --impure --expr 'let f = builtins.getFlake "git+file:///path/to/nix-configs";
  p = f.inputs.nixpkgs.legacyPackages.x86_64-linux; in
  p.stable-diffusion-cpp.override { vulkanSupport = true; }'

# image edit, 4 steps, on the R9700
sd-cli -M img_gen \
  --diffusion-model qwen-image-edit-2511-Q4_K_M.gguf \
  --vae qwen_image_vae.safetensors \
  --llm Qwen2.5-VL-7B-Instruct-Q8_0.gguf --llm_vision mmproj-F16.gguf \
  --model-args qwen_image_zero_cond_t=true \
  --lora-model-dir . \
  --backend diffusion=vulkan1,te=vulkan1,vae=vulkan1 \
  -r photo.jpg -p "turn the sky into a dramatic orange sunset <lora:Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16:1>" \
  --cfg-scale 1 --steps 4 --sampling-method euler --flow-shift 3 -o out.png
```

`--model-args qwen_image_zero_cond_t=true` is mandatory for the 2511 checkpoint; without it the
edit quality degrades noticeably.
