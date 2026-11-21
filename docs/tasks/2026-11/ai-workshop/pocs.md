---
type: Reference
description: The PoC scoreboard of the AI workshop — the state of each of the eight proofs of concept, the file or measurement that proves it, and the exact input each blocked one waits for.
task: definition.md
authored_by: agent
timestamp: 2026-11-21T21:25:00+01:00
---

# The PoC scoreboard

[definition.md](definition.md) lists eight PoCs, each with one acceptance line. This file is the state
of each one, and what it still needs. A PoC is **done** when its acceptance holds end to end; it is
**partially done** when its stages exist and have run but an input or a service is missing; it is
**blocked** when something outside the repository is absent, so no stage can start.

| PoC                | state                      | what it waits for                                         |
| ------------------ | -------------------------- | --------------------------------------------------------- |
| **VHS archive**    | **done**                   | nothing                                                   |
| **VHS restore**    | **done on synthetic data** | a capture rig, and real tapes                             |
| **documents → KB** | **blocked**                | an OCR engine, and a document corpus                      |
| **albums**         | **blocked**                | a photo collection, and the InsightFace licence decision  |
| **voice loop**     | **partially done**         | a microphone, and a wake/VAD service                      |
| **spam**           | **blocked**                | a mail corpus, and a host decision                        |
| **UI check**       | **blocked**                | `browser-harness` packaged                                |
| **LTX clip**       | **blocked**                | the LTX weight set, and the sd.cpp conv-VAE/encoder check |

## VHS archive — done

**State.** Done, on a synthetic capture, because there is no player and no capture card.

**Evidence.** [vhs-poc.md](vhs-poc.md) holds the run: `make cut freeze transcribe encode report`
took 57.13 s for a 180 s capture and produced a `cut.mkv` of 120.000 s, a `frozen.json` that classes
the 15 s hold `stuck` and the 5 s hold `freeze`, the spoken sentence word for word, and a
`report.json`; `make vmaf` reported mean 96.94 against a floor of 93; and a second identical run was
`Nothing to be done` for all five targets, 0.00 s. The acceptance's three parts therefore hold: one
command cuts a capture to its content, a re-run is a no-op, and the notification stays a placeholder
(`notify` only fires when `~/.config/ntfy/topic` exists,
[hack/media/README.md](../../../../hack/media/README.md)).

**Waits for.** Nothing. The capture shape is the only synthetic part, and every stage is the same
command on a real tape.

## VHS restore — done on synthetic data

**State.** All the stages exist and have run on the stand-in: deinterlace, video denoise, audio
denoise, master, and the VMAF gate. The acceptance is not met for real input.

**Evidence.** The stage table in [vhs-poc.md](vhs-poc.md) is the proof: `deint` 7.15 s → a 50 fps
`deinterlaced.mkv`, `denoise` 7.83 s, `audio` 0.74 s, `master` 23.24 s → AV1 10-bit + Opus at the
capture's own 576 lines, and `vmaf` mean 96.94 / min 95.23. The audio branch took the `ffmpeg`
`afftdn` path, because the `deepFilter` CLI is not packaged
([hack/media/README.md](../../../../hack/media/README.md), "What is packaged today").

**Waits for.** Two inputs, both external:

- **A capture rig.** Time-base error needs a TBC in the VCR or a frame store, tracking error needs a
  per-tape procedure and often a second VCR, and dropouts need clean tape. "The bench cannot rescue a
  bad capture. TBC, tracking and cleaning happen before the file exists"
  ([video-analysis/definition.md](../video-analysis/definition.md), Part 1).
- **Real tapes.** A synthetic track is digital silence around one sentence, so `afftdn` had nothing
  to remove; tape hiss is the case the audio denoise exists for.

## documents → KB — blocked

**State.** Blocked before its first stage. Nothing is registered to turn a scan into text.

**Evidence.** No OCR model is registered: [data/llm.nix](../../../../data/llm.nix) and
[hosts-den/brys/policy.nix](../../../../hosts-den/brys/policy.nix) name no `dots.ocr` and no
PaddleOCR-VL, and `packages/` holds no OCR package. The patched nixpkgs tree does carry
`paddleocr` and `unstructured`, so the packaging route exists; no model is downloaded, measured or
admitted. The corpus is thin rather than absent: a private document tree exists on the owner's
workstation (a Nextcloud folder, mostly digital-native PDFs and a handful of real scans), it is on no
engine host, and no ingest path is approved.

**What already exists.** The embedding half. `qwen3-embedding-4b` is registered in
[data/llm.nix](../../../../data/llm.nix) (alias `embed-std-fast`, 8192 context, CPU only), and the
policy carries it with estimated facts. The index and the media ingest are designed but not built
([local-rag-index](../local-rag-index/definition.md),
[rag-media-ingest](../rag-media-ingest/definition.md)).

**Waits for.** An OCR engine as a measured profile — `dots.ocr` (GPU, Apache-2.0) or PaddleOCR-VL —
and a document corpus: a scanned PDF set with a known content, so a paraphrase query can be scored.

## albums — blocked

**State.** Blocked. There is no photo collection, and the face step needs a licence decision.

**Evidence.** No album corpus exists on an engine host. Ente is only the desktop client
(`modules/universal/programs/ente-photos`); PhotoPrism exists as a module
(`modules/universal/programs/photoprism`, whose originals device points at a Nextcloud photo folder),
but no host enables it; and the owner's image tree is screenshots and document photos rather than a
photo library. The face-clustering model is `insightface`: its code is MIT
(`pkgs/development/python-modules/insightface` in the patched nixpkgs), but its pretrained models are
released for non-commercial research only, and that decision is not recorded anywhere.

**What already exists.** The describe-then-index design
([rag-media-ingest](../rag-media-ingest/definition.md)), the reviewer `qwen2.5-vl-7b` as the caption
model, and `qwen3-embedding-4b` for the album text.

**Waits for.** One exported photo folder (an Ente export is the natural source, and its
`source_ref` scheme `ente:<assetId>` is already the design's), and a written InsightFace decision —
either accepted for private use, or replaced by a face model with a permissive model licence.

## voice loop — partially done

**State.** The speech legs are proven and the agent leg is live. The loop's ends are missing: nothing
listens, and nothing speaks on demand.

**Evidence.** Both speech legs round-trip on `brys`, measured 2026-11-21: Piper wrote 136,236 bytes
of WAV for one sentence, and `whisper-cli` transcribed it back word for word
([hack/media/README.md](../../../../hack/media/README.md), "Speak"); the same chain produced the
word-for-word transcript of the archive run ([vhs-poc.md](vhs-poc.md), "The transcript contains the
spoken sentence"). The agent in the middle needs no work: Hermes Agent is live on `etra` and answers
as `qfn` ([definition.md](definition.md), "Hermes Agent on `etra` (live)").

**Waits for.**

- **A microphone.** `brys` exposes one analog capture PCM (`02-00: ALC1220 Analog … capture 1` in
  `/proc/asound/pcm`), but nothing sources it: no microphone is connected, and no audio server or
  capture unit is configured.
- **A wake/VAD service.** The repository names no wake-word detector and no VAD at all; `whisper`
  is run per file, not on a stream.
- **A voice other than Piper.** Kokoro is not in nixpkgs, so Piper is the stand-in
  ([hack/media/README.md](../../../../hack/media/README.md), "What is packaged today").

## spam — blocked

**State.** Blocked. There is no corpus to train on and no place to run the loop.

**Evidence.** The fleet has no mail server and no configured mailbox: `services.offlineimap.install`
is set on workstations, but no account exists, and no host file under `hosts/`, `hosts-den/` or
`modules/universal/` declares a mail server. The only artefact of this PoC is its acceptance line and
the sealed-split rule (definition.md, A10: the builder never reads the eval split, and a check fails
when its hash changes).

**Waits for.** A labelled mail corpus with a sealed split, and a host decision — which machine holds
the mailbox copy, and which machine runs the agent loop.

## UI check — blocked

**State.** Blocked at its first step. Neither the browser driver nor the screenshot step exists.

**Evidence.** Hermes hides `browser_exec` instead of failing: the container log shows
`browser_exec_available returned False`, and `hermes doctor` reports `✓ browser`, `✓ browser-use` and
`⚠ Chromium not installed (browser_exec cannot start a local browser)`
([definition.md](definition.md); [browser-harness/definition.md](../browser-harness/definition.md),
"Context"). The packaging task's first item — establish what `browser-harness` wraps from its
`pyproject` — has not run.

**Waits for.** `browser-harness` packaged in `packages/browser-harness/`, or the recorded decision
that its dependencies are missing; then a Chromium service with a CDP endpoint (proposed on `brys`,
loopback or tailnet only, because CDP is unauthenticated RCE in a browser profile).

## LTX clip — blocked

**State.** Blocked. No LTX weight is present, and the renderer is unverified for LTX.

**Evidence.** No LTX profile exists: [data/llm.nix](../../../../data/llm.nix) and
[hosts-den/brys/image-models.nix](../../../../hosts-den/brys/image-models.nix) name no LTX file, and
no `LTX*` GGUF sits in the models dataset. The model is the 22B LTX-2.5, gated, under the LTX
community licence rather than Apache, and 32 GB of VRAM minimum
([image-video-editing-models/definition.md](../image-video-editing-models/definition.md), the LTX
row). The renderer is the open question: "LTX-2.5's encoder and conv VAE are unverified in sd.cpp"
(definition.md, "Convergence").

**Waits for.** The LTX weight set (text encoder, conv VAE and DiT) in the models dataset, and one
sd.cpp run that decodes the conv VAE — the check that decides whether LTX belongs to the sd.cpp
image profiles or to ComfyUI.

## What finishing needs, one line each

| PoC            | to be finished it needs                                                                                                                          |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| VHS archive    | nothing — done; only the `notify` target stays a placeholder                                                                                     |
| VHS restore    | one real tape through a TBC-stabilised capture, plus the `deepFilter` CLI packaged for a track that has hiss                                     |
| documents → KB | `dots.ocr` or PaddleOCR-VL registered as a measured profile, plus a scanned-PDF corpus on an engine host that a paraphrase can be scored against |
| albums         | one exported photo folder, VLM captions over it, and a recorded InsightFace licence decision                                                     |
| voice loop     | a microphone on a client host, a wake/VAD loop, and a voice model — Kokoro packaged, or Piper accepted as the voice                              |
| spam           | a labelled mail corpus with a sealed split, and a named host for the loop                                                                        |
| UI check       | `browser-harness` packaged, a CDP browser service, then screenshot → VLM verdict                                                                 |
| LTX clip       | the gated LTX-2.x weights in the models dataset, and an sd.cpp run that decodes LTX's conv VAE                                                   |

## Which to start next

**Start the voice loop.** It is the only PoC whose whole remaining input is one cheap microphone:
both speech legs already round-trip on `brys`, the agent it must reach is live on `etra`, and it runs
on a GPU-less client host, so it costs the card nothing. Its packaging work — whisper-turbo,
DeepFilterNet's CLI, Kokoro — is the same work that the restore PoC's audio half waits for
(definition.md, "Order of work", step 2), so one effort unblocks two PoCs.

**documents → KB** is the other candidate, and it is the one that pays in daily work rather than in
media: its embedding half is registered, but the first stage needs an OCR engine and a corpus before
anything can run.
