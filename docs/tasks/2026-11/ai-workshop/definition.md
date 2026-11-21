---
type: Task
description: Umbrella task for the AI workshop — the engine/client split, the shared bench, the model catalogue, and the end-to-end PoCs that prove each capability before it is needed.
status: open
authored_by: agent
timestamp: 2026-11-21T08:00:00+01:00
---

# AI workshop

## Purpose

Prepare the bench, not the products. Every future media, document, audio or agent task should be a
target on an existing bench with measured models behind it, so starting the work is a decision, not
a build.

The coding and infrastructure work stays the primary mode. Everything else is a capability that is
_ready_ — wired, measured, and proven once — and idle until it is needed.

## The split that everything hangs on

| side          | hosts                                                   | what runs there                                                                                                                     |
| ------------- | ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **engine**    | brys (R9700, 32 GB)                                     | strata profiles (`qfn`), `sd-server` editors, `llama-server` companions and small models, the placement tree                        |
| **client**    | oams (12 GB 6800M), etra (no GPU), later GPU-less boxes | harnesses (OpenCode, Pi), Hermes Agent gateway, ComfyUI UI, browser, MCP clients, CPU models (Kokoro, DeepFilterNet, whisper-turbo) |
| **transport** | etra                                                    | litellm gateway, Caddy with auth, ntfy                                                                                              |

A PoC declares which side each step runs on. Anything that needs a GPU is engine; anything that is a
UI, a harness, a scheduler or a CPU model is client. That line is what lets a future 4-core box join
without redesign.

## Slots

| slot        | contents                                                                                                                                                      | state                       |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| `engine`    | profiles, the placement tree, `/decide` + `/admit`, response identity headers                                                                                 | live                        |
| `client`    | harnesses on oams; Hermes Agent on etra; ComfyUI decision pending                                                                                             | partly                      |
| `bench`     | `hack/media/` DAG runner, asset layout, ntfy, resumable stages                                                                                                | **this task**               |
| `catalogue` | 10 models with fast/quality variants, all measured                                                                                                            | 23 registered, 15 estimated |
| `services`  | every long-running service as an OCI image built by Nix, run by `virtualisation.oci-containers`: devices, volumes and environment declared in the host module | **rule**                    |
| `gateway`   | Hermes Agent (MIT, self-hosted) as the phone/cron/browser front door                                                                                          | missing                     |
| `crew`      | multi-agent orchestration: LangGraph _or_ Hermes sub-agents, one only                                                                                         | missing                     |
| `spam`      | agent-driven development loop for a mail classifier                                                                                                           | missing                     |
| `policy`    | the tree extended with the new kinds (audio, OCR, restoration, LTX)                                                                                           | live, facts incomplete      |

## PoCs, each with an acceptance

| PoC                | steps                                                                                                                     | acceptance                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| **VHS archive**    | capture → black/silence detect → cut → probe → notify                                                                     | one command cuts a capture to its content and pings ntfy; re-running is a no-op                |
| **VHS restore**    | deinterlace → video denoise → audio denoise (DeepFilterNet) → optional upscale/interpolate → encode (SVT-AV1 + VMAF gate) | a 5-minute capture produces a master whose VMAF is above the floor and whose audio has no hiss |
| **documents → KB** | OCR (dots.ocr) → chunk → embed (qwen3-embedding) → index → search                                                         | a scanned PDF is findable by a paraphrase of its content                                       |
| **albums**         | EXIF + embeddings + face clusters → VLM captions → narrative                                                              | a trip folder becomes one album with a written summary                                         |
| **voice loop**     | wake/VAD → whisper-turbo → agent → Kokoro                                                                                 | a spoken command reaches an agent session and the answer is spoken back                        |
| **spam**           | corpus → rules/model → sealed eval → reviewer                                                                             | precision and recall on the sealed split both improve, and the split hash is unchanged         |
| **LTX clip**       | text → LTX-2.3 (or 2.5) → mp4 with audio                                                                                  | one 5-second clip with synchronised audio, timed                                               |
| **UI check**       | browser driver → screenshot → VLM verdict                                                                                 | a broken layout is reported with the element that broke                                        |

## Measurements the scheduler needs

The placement tree is only as good as its facts. For every model the bench can invoke, stage 0
records VRAM, RAM, load seconds, switch seconds, decode t/s alone and beside each colo profile, and
`minResidencySeconds`. Until a model has numbers it is refused (I22), which is deliberate.

Known gaps today: 15 catalogue models are estimated from GGUF size; the audio, OCR, restoration and
LTX models have no numbers at all.

## Attack review (five rounds)

**R1 — capacity and co-residency.**

- **A1** a `make` step that needs a GPU model knows nothing about the placement tree and fails
  mid-run. _Fix_: every GPU step goes through a wrapper that calls `/admit`, records the decision
  and waits on `wait` verdicts. The bench never starts a model directly.
- **A2** two PoCs at once both want the reviewer or the upscaler, and only one is admissible.
  _Fix_: a job lock per GPU class, taken for the duration of a GPU step, so the second job waits
  instead of being refused halfway.

**R2 — time and concurrency.**

- **A3** a tape is hours long and a run can die halfway; a half-written output must not count as
  done. _Fix_: every stage writes `.tmp` and renames, which is what `make` needs to resume safely.
- **A4** a long upscale blocks interactive `qfn`. _Fix_: heavy GPU steps run as `class: batch` (the
  cooldown exemption) and, by default, under a Hermes cron window at night.

**R3 — engine/client split.**

- **A5** the capture lands on brys but review happens on oams. _Fix_: the asset layout defines
  `incoming/`, `proxies/`, `masters/`, `archive/`; masters stay on brys, proxies are rsynced to
  oams by a bench target.
- **A6** Hermes on etra dies when litellm is down. _Fix_: two endpoints configured — litellm first,
  brys direct as fallback — and a health check in the gateway unit.

**R4 — operability.**

- **A7** the new models need ~35 GB (LTX ~30, audio ~5, OCR ~2, restoration ~2) against ~152 GB
  free. _Fix_: a disk budget step in the bench and a prune list kept in the task.
- **A8** adding eight more estimated models would make the tree a fiction. _Fix_: stage 0 is a
  blocker for every model the bench can invoke; `allowUnmeasured` stays false.

**R5 — semantics and quality.**

- **A9** multi-agent roles multiply calls and can hammer the card. _Fix_: a per-job call budget and
  the tree's cooldown; the crew declares its model set up front so the tree can refuse it whole.
- **A10** the spam loop can cheat by tuning on the eval set. _Fix_: a sealed split the builder never
  reads, and a check that fails when its hash changes.

**Convergence.** R1–R4 found real gaps (GPU admission for bench steps, atomic outputs, the asset
share, the disk budget, measured facts). R5 found two (call budget, sealed split). A sixth pass with
the same lens found no new class, so the loop stops. Residual, not defects: LTX-2.5's encoder and
conv VAE are unverified in sd.cpp, and Hermes Agent has no Nix packaging yet.

## Order of work

1. **bench** — `hack/media/` runner, asset layout, ntfy, atomic stages, GPU admission wrapper.
2. **audio** — Kokoro, whisper-turbo, DeepFilterNet, Demucs; they unlock the VHS audio half and the
   voice loop, and most run on a GPU-less host.
3. **catalogue prune + stage-0 measurements** — the tree stops guessing.
4. **gateway** — Hermes Agent on etra, wired to the fleet, with the VHS watcher as its first cron.
5. **PoCs in order**: VHS archive → VHS restore → documents → albums → spam → voice → UI → LTX.
6. **crew** — only when a PoC has shown that one agent is not enough.

## Services are containers

A service that might move must not depend on the host it was built for. The rule:

- **Packaging**: `pkgs.dockerTools.buildImage` (or the project's own image), built by the flake, so
  the image is reproducible and versioned with the repo.
- **Running**: `virtualisation.oci-containers.containers.<name>` in the host module, with `volumes`
  for state, `extraOptions` for devices (`/dev/dri` for Vulkan, `/dev/kfd` for ROCm), and
  `environment` for the fleet's endpoint and key.
- **The unit of migration is image + volume.** Moving Hermes Agent from etra to a new box is a
  ten-line module and an rsync of `~/.hermes`.
- **CPU-only hosts run the same image.** Kokoro, DeepFilterNet and whisper-turbo have no device
  requirement, so the identical image runs on a 4-core box with no GPU.
- **The bench stays host-native** — it is a shell of `ffmpeg` calls and file targets, not a service.
  The tools it calls are Nix packages or containers, never a hand-installed binary.
- **GPU containers do not get to bypass the policy**: a container that starts a model server is
  registered as an engine profile like any other, and `admit` still decides.

## Non-goals

ComfyUI is not adopted until a PoC needs a tensor graph sd.cpp cannot express; etra never runs
inference; no hosted service becomes a dependency.
