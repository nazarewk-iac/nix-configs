# The media bench

One `Makefile` per capture, every stage a file target. `make` resumes after a failure and re-runs
only what changed — which is what a two-hour tape needs.

```sh
# from the repository root
make -f hack/media/Makefile cut SRC=/data/vhs/tape-07.mkv OUT=/data/vhs/tape-07.work
make -f hack/media/Makefile encode SRC=/data/vhs/tape-07.mkv OUT=/data/vhs/tape-07.work
make -f hack/media/Makefile vmaf   SRC=/data/vhs/tape-07.mkv OUT=/data/vhs/tape-07.work
```

| target    | produces                       | notes                                                                                            |
| --------- | ------------------------------ | ------------------------------------------------------------------------------------------------ |
| `probe`   | `probe.json`                   | ffprobe, the input of every later step                                                           |
| `cut`     | `cut.mkv`                      | drops the leading and trailing black; a fully black tape is kept whole and tagged `.broken.json` |
| `deint`   | `deinterlaced.mkv`             | `bwdif`; FFV1 so nothing is lost before denoise                                                  |
| `denoise` | `video-denoised.mkv`           | `hqdn3d`, tuned for tape grain                                                                   |
| `audio`   | `audio.wav`, `audio-clean.wav` | DeepFilterNet when installed, a copy otherwise, an empty file when the tape is silent            |
| `master`  | `master.mkv`                   | SVT-AV1 CRF 28, 10-bit, Opus 128k                                                                |
| `proxy`   | `proxy.mp4`                    | 720p H.264 for the client side                                                                   |
| `vmaf`    | —                              | fails the run when the master drops below `VMAF_FLOOR` (93)                                      |
| `notify`  | —                              | ntfy, when `~/.config/ntfy/topic` exists                                                         |

## Conventions

- **Sources are never modified.** Every output lands in `OUT`, a work directory beside the capture.
- **Atomic stages.** Each recipe writes `name.tmp.ext` and renames, so an interrupted run never
  leaves a file that looks complete.
- **Silent tapes are normal.** An empty `audio.wav` means "no audio", and the master is built
  video-only instead of failing.
- **Masters stay on the engine host**, `proxy.mp4` is the only file meant to be copied to a weaker
  client.

## What is packaged today

| need             | tool                           | licence  | note                                                                                      |
| ---------------- | ------------------------------ | -------- | ----------------------------------------------------------------------------------------- |
| speech to text   | `whisper-cpp` (`whisper-cli`)  | MIT      | CPU, offline; `parakeet-cli` ships in the same package                                    |
| text to speech   | `piper`                        | MIT      | CPU; the stand-in for Kokoro, which is not in nixpkgs                                     |
| denoise (speech) | `deepfilternet` LADSPA plugin  | MIT      | for EasyEffects; the CLI (`deepFilter`) is not packaged, so the bench uses ffmpeg filters |
| denoise (tape)   | `ffmpeg` `afftdn` + `highpass` | LGPL/GPL | no model, no download                                                                     |
| separation       | Demucs                         | MIT      | **not packaged** — needs a container or a Python env                                      |

## Where it runs

The runner is host-native (it is a shell of `ffmpeg` calls). Anything it invokes that needs a model
goes through `admit`, so the placement tree decides whether the card can take it — the bench never
starts a model server directly. Long GPU steps are meant to run from a scheduled window (Hermes cron)
as `class: batch`.
