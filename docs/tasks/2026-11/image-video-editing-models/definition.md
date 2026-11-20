---
type: Task
description: Pick the open-weight image and video editing models that fit one 32 GB R9700, decide whether they share the card with QFN or replace it, and build the serving stack that llama-swap can drive.
status: open
authored_by: agent
timestamp: 2026-11-20T15:00:00+01:00
---

# Image and video editing on the R9700

## Context

The fleet serves text, plus `qwen3-omni` for reading images and audio. Nothing edits an image or a
video. The card is one R9700 (31.86 GiB, ROCm via the shim and Vulkan), the host has 125 GiB of RAM,
and llama-swap is the front door, so a new model has to look like a llama-swap entry: a command that
serves a port.

The question this task answers: **which open-weight editors are worth running, and do they fit
beside QFN or must they evict it?**

## Shortlist, measured against this hardware

Licences first, because they eliminate more than VRAM does.

| model                                        | task                                                                             | params                            | licence                                                                | file sizes                                                                                     | verdict                                                                |
| -------------------------------------------- | -------------------------------------------------------------------------------- | --------------------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| **Qwen-Image-Edit-2511**                     | instruction image editing, multi-image, text-in-image                            | 20B MMDiT + Qwen2.5-VL-7B encoder | **Apache-2.0**                                                         | Q4_K_M 13.2 GB, Q8_0 21.8 GB, FP8 20.5 GB, BF16 40.9 GB; encoder 9.38 GB (RAM, released after) | **the quality pick**                                                   |
| **LongCat-Image-Edit(-Turbo)**               | instruction editing, bilingual text                                              | 6B                                | **Apache-2.0**                                                         | ~17 GB with CPU offload; Turbo is a 10x distilled variant; ComfyUI-native since 2026-03        | **the efficiency pick**                                                |
| FLUX.1 Kontext [dev]                         | iterative single-edit fidelity                                                   | 12B                               | non-commercial                                                         | 12 GB FP8, 7 GB NF4                                                                            | licence disqualifies it for client work                                |
| FLUX.2 [dev]                                 | multi-reference, 4 MP                                                            | 32B                               | non-commercial                                                         | 4-bit on a 4090-class card                                                                     | same licence problem                                                   |
| FLUX.2 [klein] 4B                            | fast edits                                                                       | 4B                                | Apache-2.0                                                             | 6-8 GB at 4-bit                                                                                | good fallback if latency wins over fidelity                            |
| Step1X-Edit v1.2                             | reasoning-heavy edits                                                            | MLLM + DiT                        | Apache-2.0                                                             | 34 GB FP8, 18 GB with offload                                                                  | too big for the benefit                                                |
| MiniMax-H3-Image                             | 4K generation **and** editing, 16 references, 6 steps                            | 33.1B DiT + Qwen3-VL-32B encoder  | MiniMax community: **excludes the EU, UK, KR and US**, $1M revenue cap | DiT 66 GB BF16 / 13.6 GB UD-Q4; encoder 66.7 GB BF16 / 18.2 GB Q4; ~34 GB download             | **excluded: we are in the EU**, and the encoder alone is a second card |
| Z-Image / Z-Image-Edit                       | fast generation; editing variant                                                 | 6B                                | Apache-2.0                                                             | Turbo fits 16 GB                                                                               | Edit and Omni-Base are announced, **not released** as of 2026-11       |
| ERNIE-Image (8B), GLM-Image, OmniGen2, BAGEL | generation, some editing                                                         | 4-8B                              | Apache-2.0 / MIT                                                       | 9.6-23 GB                                                                                      | viable, none beats the two picks on editing benchmarks                 |
| **Wan2.1 VACE 14B**                          | video editing: subject swap, in-video replacement, outpainting, first/last frame | 14B                               | **Apache-2.0**                                                         | fp16 ~32 GB, fp8/GGUF ~16 GB                                                                   | **the video pick**                                                     |
| Wan2.2 TI2V-5B                               | text/image to video                                                              | 5B                                | Apache-2.0                                                             | 24 GB with offload                                                                             | generation, not editing; a later add                                   |
| LTX-2.5                                      | video + synchronized audio                                                       | 22B                               | LTX community (free under $10M revenue), gated                         | 32 GB minimum, int8/GGUF 13-24 GB                                                              | good, but the licence is not Apache                                    |
| HunyuanVideo-1.5                             | text/image to video                                                              | 8.3B                              | Tencent community, **excludes the EU**                                 | 14 GB with offload                                                                             | excluded: we are in the EU                                             |

Benchmarks, from the vendors' own GEdit-Bench-EN tables (read as vendor claims): LongCat-Image-Edit
reports 7.64 overall, Qwen-Image-Edit 7.56, Step1X-Edit 6.97, FLUX.1 Kontext [dev] 6.00. LongCat is
the smallest of them at 6B, and its Turbo variant claims a 10x speedup, which matters on a batch
workload where each edit already evicts QFN.

Two facts decide the fit:

- Qwen-Image-Edit at Q8_0 is **21.8 GB** plus a 9.4 GB encoder that ComfyUI loads and releases, so
  the card holds it alone. It cannot share with QFN, which wants ~30 GB.
- Wan2.1 VACE 14B at fp8 is ~16 GB; with the text encoder and activations it wants most of the card
  too.

## Decision

Three entries are staged (two image, one video), and the image pair is a choice rather than a
duplicate: Qwen-Image-Edit-2511 for quality and text-in-image work, LongCat-Image-Edit-Turbo for
iteration speed at a third of the parameters. Only one of them is enabled after the spike.

They join the **`main` set** in `data/llm.nix`, which is the frontier's set: llama-swap
evicts `qfn` for them and they for `qfn`. That is the "EITHER that or QFN" the hardware forces, and
it is the honest model: an edit is a minutes-long batch job, not a request interleaved with coding.

`qwen3-omni` stays as it is (the reserve, the gate). It reads images; these models change them.

## The serving stack

llama.cpp cannot run a diffusion model, so the entry is not a llama-server. Two candidates, both in
nixpkgs:

| option                              | why                                                                                         | why not                                                                                                                  |
| ----------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **`stable-diffusion-cpp`** (Vulkan) | no torch, no ROCm stack, same shape as llama.cpp: a GGUF on the card, a small server binary | feature lag: Qwen-Image-Edit support has to be checked against the pinned version; server API is A1111-style, not OpenAI |
| `comfyui` (ROCm torch)              | every workflow and every quant exists; Qwen-Image-Edit and VACE templates are native        | a multi-GB torch/ROCm stack on a host whose ROCm path already needs a shim, plus custom nodes and a workflow JSON to pin |

Start with `stable-diffusion-cpp` on Vulkan: it matches how llama.cpp already reaches this card, it
is one binary, and a failure there is a model-support question rather than a Python dependency
question. Fall back to ComfyUI only if the pinned sd.cpp cannot run Qwen-Image-Edit.

## Survey results (measured)

Full timings, images and the two traps are in [measurements.md](measurements.md). The short form,
1024x1024, one photograph, one instruction. Two wall times are given because they answer two
different questions: **210 W** is the production cap (the VBIOS floor), **300 W** is the card's
ceiling and the objective, policy-free number.

| model                                                   | steps | 210 W  | 300 W    | peak VRAM | verdict                                         |
| ------------------------------------------------------- | ----- | ------ | -------- | --------- | ----------------------------------------------- |
| **Qwen-Image-Edit-2511 Q4_K_M + Lightning 4-step LoRA** | 4     | 44 s   | **41 s** | 26.2 GiB  | **the pick**: best fidelity per second          |
| Qwen-Image-Edit-2511 Q4_K_M                             | 20    | 293 s  | 266 s    | 25.4 GiB  | same model, no LoRA, 6.7x the time              |
| LongCat-Image-Edit-Turbo, official bf16                 | 8     | 30 s   | **29 s** | 22.9 GiB  | fastest, follows the instruction more literally |
| LongCat-Image-Edit-Turbo, third-party Q8_0 GGUF         | 8     | 25 s   | —        | 17.4 GiB  | **broken conversion: noise**                    |
| Wan2.1 VACE 14B, 832x480 x 33 frames                    | 20    | 1039 s | 940 s    | 28.6 GiB  | works; 2 s of video for a quarter of an hour    |

The power cap costs 3-10 % of wall time and buys back 90 W of heat. That is the right trade for a
host that sits in a room, and it is why the production cap stays at 210 W while the table keeps the
300 W column for comparison with other cards.

Two facts that the plan did not anticipate:

1. **Device order.** `sd-cli` enumerates the 4 GB RX 550 as `vulkan0` and the R9700 as `vulkan1`.
   The first run silently used the RX 550 at 147 s/it. Every entry must pin the device, preferably
   with `GGML_VK_VISIBLE_DEVICES=1`.
2. **Not every GGUF is a conversion.** The LongCat GGUF named in the model list loads cleanly and
   produces noise; the official safetensors is correct. Prove a new model with official weights
   before trusting a quantisation of it.

The stack decision holds: `stable-diffusion-cpp` with `vulkanSupport = true` runs every model on
the shortlist, needs no torch, and is a single binary. ComfyUI is not needed.

## Serving: implemented and proven

The three editors are **profiles of the manager**, not separate servers:

| profile         | port | command                                                    |
| --------------- | ---- | ---------------------------------------------------------- |
| `image-qwen`    | 8091 | `sd-server` + Qwen-Image-Edit-2511 Q4_K_M + Lightning LoRA |
| `image-longcat` | 8092 | `sd-server` + LongCat-Image-Edit-Turbo bf16                |
| `image-vace`    | 8093 | `sd-server` + Wan2.1 VACE 14B Q4_K_M                       |

`data/llm.nix` registers each as a llama-swap model whose `cmd` is
`strata-select image-<name> --port ${PORT}`. So a request for an editor asks the manager for that
profile: the manager drains, stops the frontier, drops the cache and starts `sd-server`. A later
`qfn` request evicts the editor the same way. The card is never double-booked because there is only
one thing that switches it.

Four details that are load-bearing, each found by breaking it:

1. **One port per profile.** A stopped `sd-server` leaves TIME_WAIT sockets on its port, and the
   strata engine's plain `bind()` reports "already in use" for a minute. The frontier keeps 8080;
   each editor gets its own port. The manager reports the port in the `/select` reply, so the
   proxy always forwards to the right one.
2. **`cmdStop` plus a proxy that leaves.** llama-swap runs `cmdStop` (`ctl down`) and then waits for
   the entry process to exit; a proxy that outlives its profile blocks the next model until
   llama-swap's 15-minute kill timeout. `strata-select` now watches `/status` and exits when the
   manager leaves the profile it selected. `auto` (`qfn`) is exempt: staying alive across a switch
   is what that name promises.
3. **`checkEndpoint: /sdapi/v1/options`.** llama-swap's default health path is not an A1111 path;
   without this it marks a working editor as broken and kills it.
4. **`unlisted: true`.** `/v1/models` is the chat catalogue. The editors stay addressable through
   llama-swap's `/upstream/<model>/...` passthrough:
   `POST /upstream/qwen-image-edit/sdapi/v1/txt2img`.

The gate is the manager's own profile table plus two rules: `qfn` (`auto`) refuses to keep a
running image profile and answers with `kdn_switch_to: max`, and the `qwen3-omni` gate keeps its
`requireProfiles` check, so a companion request while an editor holds the card is refused with the
same readable error instead of competing for VRAM.

Measured on brys after the deploy: an edit through llama-swap at 384x384/4 steps returns in ~2 s
with the profile warm; the eviction `image-qwen` -> `qfn` completes in **69 s** (stop, cache drop,
max load) and the answer comes back from `qwen3.8-flash-next-unsloth-ud-iq4_xs`. A cold editor load
is ~40 s.

## Driving an edit: read and adjust, without generating

The editors generate pixels. The _decision_ — which shot is the keeper, what changed, where to cut
— is a different job, and a vision model that only answers text does it better and cheaper.

**`qwen2.5-vl-7b` is served as a `reviewer`** (router `surveyed`, gate identical to the companion's,
`ttl = 3600`). It is the same file the image editors load as their text encoder, hard-linked into
`models/qwen2.5-vl-7b/`, so it costs disk nothing.

- It **co-resides with the frontier**: measured 22.2 GiB of VRAM with the IQ2_XS engine loaded, and
  `qfn` kept answering while it was loaded. Reviewing a cut does not evict the frontier.
- It **shares the companion's gate**: without a reserve it answers `409` naming
  `kdn_switch_to: omni-fast`; with the field it switches, loads and answers in one request (74 s).
  `modelsMax = 1` on the router means the reviewer and `qwen3-omni` evict each other, so the two
  never fight for the reserve.

**The tool** is `hack/video-edit.py`: ffmpeg scene detection and sampling → one schema-constrained
request → validation → apply with ffmpeg, plus an MLT project for a Kdenlive review pass.

| measured                                     | value                                                  |
| -------------------------------------------- | ------------------------------------------------------ |
| tokens per 832x480 frame                     | ~400                                                   |
| 3 frames                                     | 1274 prompt tokens, 2 s                                |
| 12 frames                                    | 4791 prompt tokens, 8 s                                |
| frames per request at the 16k served context | ~30, i.e. ~60 s of footage at 1 frame/2 s              |
| hand plan (cut 2.05-5.05 of a 7.13 s clip)   | 4.13 s output, boundaries snapped to the detected cuts |

The division of labour is the point: the model's timestamps are _intent_, so the tool snaps every
boundary to a detected scene cut and validates the result. A 7B model sees one frame every few
hundred milliseconds; it cannot place a cut at 1.37 s, and a tool that trusts it will.

## What the user actually touches

A diffusion model is not a chat endpoint. These are the clients, and they split across two hosts:

| piece                                        | runs on                          | why                                                                                                   |
| -------------------------------------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------- |
| ComfyUI (or a `stable-diffusion-cpp` server) | **brys**                         | the card and the weights live there; the UI is a browser on any machine                               |
| Krita + the "AI Diffusion" plugin            | **the workstation** (oams, anji) | brush, mask and layer editing against a remote ComfyUI backend: this is the "AI-enabled image editor" |
| a browser tab to ComfyUI                     | anywhere                         | the node-graph surface for multi-image edits and the VACE video templates                             |
| an NLE (Kdenlive, DaVinci)                   | the workstation                  | VACE produces clips; the timeline work is not model-aware                                             |

So the model host and the editing host are different machines, and only the first needs a GPU. A
Krita session on oams paints locally and posts an image plus an instruction to brys.

**llama-swap is the wrong front door for these.** It speaks OpenAI chat and answers `/v1/models`; an
image model answers neither. The exclusive-with-QFN rule therefore has to move: either the manager
gains an `image` profile that stops the engine and starts the ComfyUI/sd.cpp server (the adapter is
already the place for "which command serves which profile"), or ComfyUI runs as its own unit and
asks the manager for a switch before it starts. The first fits the design; the second needs a new
hook. This is the decision item 1 of the work plan should settle.

## What fits on oams (12 GB RX 6800M, 62 GB RAM)

Measured or published figures, for a laptop that is 6-9x slower than the R9700 but idle most days:

| model                                             | oams                                    | note                                     |
| ------------------------------------------------- | --------------------------------------- | ---------------------------------------- |
| OmniGen2 (4B)                                     | **fits** (9.6 GB fp16 measured)         | composition + editing, Apache            |
| ERNIE-Image Turbo (8B, Q8 GGUF)                   | **fits** (9.1 GB measured)              | generation, not editing                  |
| Z-Image Turbo (6B, Q8)                            | **fits** (9.1 GB measured)              | fast generation; Edit variant unreleased |
| Qwen-Image-Edit-2511 Q3_K_S                       | fits (9.2 GB) with visible quality loss | below the Q4 floor this model wants      |
| FLUX.2 [klein] 4B                                 | fits (~8-13 GB)                         | Apache, generation + edits               |
| LongCat-Image-Edit-Turbo (6B)                     | fits with CPU offload (~17 GB), slower  | the best editing quality per byte        |
| Wan2.2 TI2V-5B, VACE 1.3B                         | fit (~7-8 GB)                           | small video, 480p class                  |
| Qwen-Image-Edit Q8, VACE 14B, LTX-2.5, MiniMax H3 | **no**                                  | 14-66 GB of weights                      |

That is the useful split: **oams is the prototyping box** for the small editors (LongCat-Turbo,
OmniGen2, klein 4B) and brys is the production box for the 20B and 14B ones.

## Can an editor share the card with QFN or omni?

The arithmetic, on 31.86 GiB:

| resting state                                 | used     | free   | what fits beside it                                    |
| --------------------------------------------- | -------- | ------ | ------------------------------------------------------ |
| `qfn-max` (whole card)                        | ~30 GB   | ~1 GB  | nothing                                                |
| `qfn-colo` (reserve profile, omni not loaded) | ~10.5 GB | ~21 GB | any editor up to ~20 GB, **but then omni cannot load** |
| `qfn-colo` + omni                             | ~30.5 GB | ~1 GB  | nothing                                                |

So the answer is **no, not alongside the frontier**: `qfn-max` leaves a gigabyte, and the colo
profiles only leave room for an editor by giving up the companion's reserve. An editor is an
exclusive mode, which is what the `main` set already encodes.

## Work items

1. **Decide where exclusivity lives.** The manager gains an `image` profile (adapter = `command`,
   readiness path = the ComfyUI root) or ComfyUI asks the manager for a switch before it starts.
   Everything else in this plan depends on that answer.
2. **Prove the runtime.** Build `stable-diffusion-cpp` with Vulkan on brys, run Qwen-Image-Edit-2511
   Q8_0 (or Q4_K_M if memory is tight) through its server on `:8090`, and time one edit at
   1024×1024 with the 4-step Lightning LoRA. Acceptance: one edited image, under two minutes, card
   stays under 31 GiB.
3. **Add the entry.** `data/llm.nix` gains `qwen-image-edit` with `set = "main"`, a `command` that
   starts the sd.cpp server on `${PORT}`, and `contextSize` set to what the wrapper accepts. The
   model file lives under the persisted tree, so a second machine shares it.
4. **Video, second.** Wan2.1 VACE 14B at fp8, same path. It is a bigger download and a slower job;
   it lands only after the image editor is proven, and it may need the GGUF route.
5. **Re-measure the switch cost.** An edit request evicts QFN: measure the reload for the image model
   the way the text profiles were measured, and record it in the task's `solution.md`.

## Risks

- **ROCm/Vulkan coverage.** sd.cpp on Vulkan is the least-tested path on this card; the first spike
  is a smoke test, not a benchmark.
- **Disk.** Qwen-Image-Edit at Q8_0 plus the encoder is ~31 GB; VACE fp8 is ~16 GB. The LLM dataset
  has ~152 GB free, so both fit, but the download is a long WAN job and `wan-shaping.nix` caps it.
- **Expectation setting.** These are batch tools. A single edit is tens of seconds to minutes, and
  the card cannot serve text while it runs. That is why the entry is exclusive, not colocated.

## Follow-up

The entries are added with `enable = false` until item 1 passes, so the fleet config states the
intent without advertising a model that nothing serves yet.
