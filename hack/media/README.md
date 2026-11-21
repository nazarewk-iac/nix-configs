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
| `proxy`   | `proxy.mp4`                    | at most 720 lines, 8-bit H.264, for the client side                                              |
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
| text to speech   | `piper-tts` (`piper`)          | MIT      | CPU; the stand-in for Kokoro, which is not in nixpkgs                                     |
| denoise (speech) | `deepfilternet` LADSPA plugin  | MIT      | for EasyEffects; the CLI (`deepFilter`) is not packaged, so the bench uses ffmpeg filters |
| denoise (tape)   | `ffmpeg` `afftdn` + `highpass` | LGPL/GPL | no model, no download                                                                     |
| separation       | Demucs                         | MIT      | **not packaged** — needs a container or a Python env                                      |

The nixpkgs attribute for the TTS engine is `piper-tts`. `piper` alone is the GTK front end for the
`ratbagd` mouse config daemon, and installing it gives no speech.

## The audio models

Both are CPU-only and **not** llama-swap entries: whisper.cpp and Piper speak their own protocols,
not the OpenAI chat API, so they do not belong in `data/llm.nix` and the placement tree never sees
them. The model files sit on the shared LLM tree, beside the weights, so a second machine that
mounts that dataset gets them too. The host installs `whisper-cpp` and `piper-tts`
(`hosts-den/brys/default.nix`).

| model   | file                                                                       | size   |
| ------- | -------------------------------------------------------------------------- | ------ |
| Whisper | `/var/lib/kdn/llms/models/whisper/ggml-base.en.bin`                        | 148 MB |
| Piper   | `/var/lib/kdn/llms/models/piper/en_US-lessac-medium.onnx` and `.onnx.json` | 63 MB  |

Both were downloaded from Hugging Face (`ggerganov/whisper.cpp` and `rhasspy/piper-voices`) and are
world-readable files under the persistent `usr/data` dataset, so they survive a reboot.

### Transcribe

```sh
# a text file beside the audio
whisper-cli -m /var/lib/kdn/llms/models/whisper/ggml-base.en.bin \
  -f audio.wav -l auto -otxt

# straight to stdout, no timestamps
whisper-cli -m /var/lib/kdn/llms/models/whisper/ggml-base.en.bin \
  -f audio.wav -l auto -nt -np
```

`whisper-cli` reads flac, mp3, ogg and wav. The `transcript` target of the Makefile calls it with
`WHISPER_MODEL` (default: the path above) and skips the step, without failing the run, when the
model file is absent.

### Speak

```sh
# text on stdin, WAV on disk
echo "The media bench transcribes tape and speaks the transcript." |
  piper --model /var/lib/kdn/llms/models/piper/en_US-lessac-medium.onnx -f out.wav

# a text file in, 22 kHz mono WAV out
piper --model /var/lib/kdn/llms/models/piper/en_US-lessac-medium.onnx \
  --input-file script.txt -f out.wav
```

Piper finds the voice config next to the model (`<model>.onnx.json`), so both files must stay
together. The output is 16-bit PCM, 22 050 Hz, mono — what `whisper-cli` reads back unchanged.
`--length-scale` (slower speech) and `--sentence-silence` are the two knobs worth trying first.

Verified on `brys` on 2026-11-21: Piper wrote 136 236 bytes of WAV for that one sentence, and
`whisper-cli` transcribed it back word for word.

## Where it runs

The runner is host-native (it is a shell of `ffmpeg` calls). Anything it invokes that needs a model
goes through `admit`, so the placement tree decides whether the card can take it — the bench never
starts a model server directly. Long GPU steps are meant to run from a scheduled window (Hermes cron)
as `class: batch`.

`ffmpeg` must be the **`ffmpeg-full`** variant: plain `ffmpeg` from nixpkgs carries `libsvtav1` but
not `libvmaf`, so `make vmaf` cannot run with it. `brys` does not ship either in its host profile
today, so a run there takes the binaries from the package set:

```sh
export PATH=$(nix shell nixpkgs#ffmpeg-full -c bash -c 'dirname $(command -v ffmpeg)'):$PATH
```

The synthetic capture that proved the archive half, with the per-stage timings and the verification
output, is recorded in
[docs/tasks/2026-11/ai-workshop/vhs-poc.md](../../docs/tasks/2026-11/ai-workshop/vhs-poc.md).
