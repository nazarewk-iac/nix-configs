# The media bench

One `Makefile` per capture, every stage a file target. `make` resumes after a failure and re-runs
only what changed — which is what a two-hour tape needs.

```sh
# from the repository root
make -f hack/media/Makefile cut SRC=/data/vhs/tape-07.mkv OUT=/data/vhs/tape-07.work
make -f hack/media/Makefile encode SRC=/data/vhs/tape-07.mkv OUT=/data/vhs/tape-07.work
make -f hack/media/Makefile vmaf   SRC=/data/vhs/tape-07.mkv OUT=/data/vhs/tape-07.work

# the whole archive half, with the freeze check and the report
make -f hack/media/Makefile cut freeze transcribe encode report \
  SRC=/data/vhs/tape-07.mkv OUT=/data/vhs/tape-07.work

# drop the intermediates once the master exists; the archive stays
make -f hack/media/Makefile clean SRC=/data/vhs/tape-07.mkv OUT=/data/vhs/tape-07.work
```

| target    | produces                       | notes                                                                                            |
| --------- | ------------------------------ | ------------------------------------------------------------------------------------------------ |
| `probe`   | `probe.json`                   | ffprobe, the input of every later step                                                           |
| `cut`     | `cut.mkv`, `cut.json`          | drops the leading and trailing black; a fully black tape is kept whole and tagged `.broken.json` |
| `freeze`  | `frozen.json`                  | `freezedetect`; every held span, classed `stuck` (> 10 s) or `freeze`                            |
| `deint`   | `deinterlaced.mkv`             | `bwdif`; FFV1 so nothing is lost before denoise                                                  |
| `denoise` | `video-denoised.mkv`           | `hqdn3d`, tuned for tape grain                                                                   |
| `audio`   | `audio.wav`, `audio-clean.wav` | DeepFilterNet when installed, a copy otherwise, an empty file when the tape is silent            |
| `master`  | `master.mkv`                   | SVT-AV1 CRF 28, 10-bit, Opus 128k, **at the capture's own resolution**                           |
| `proxy`   | `proxy.mp4`                    | at most 720 lines, 8-bit H.264, for the client side                                              |
| `report`  | `report.json`                  | the archive report; fails when the master is larger than the source                              |
| `enhance` | `enhanced.review-required.mkv` | **not the archive** — a tagged upscale for a human to review, refuses at or above the target     |
| `vmaf`    | —                              | fails the run when the master drops below `VMAF_FLOOR` (93)                                      |
| `clean`   | —                              | drops the intermediates; a later `make` re-encodes the master from `cut.mkv`                     |
| `notify`  | —                              | ntfy, when `~/.config/ntfy/topic` exists                                                         |

## Two rules about the picture

Both are enforced by a target, not by a comment, because both are the kind of thing a bench does by
accident.

### Archiving never upscales

`master` keeps the resolution of the capture. There is no `scale` filter in its recipe and none may
be added: a VHS tape holds a fixed number of lines, and a bigger frame invents the rest. `report`
compares the master against the source and **fails** when the master came out larger, so an
accidental `scale=1280:720` cannot reach an archive unnoticed. `proxy` is bounded the same way
(`scale=-2:'min(720,ih)'`), so an SD master never produces a larger proxy.

`enhance` is the one upscale in the file and it is deliberately outside the archive:

- it is **not** in `all`, and nothing depends on it, so no ordinary run produces it;
- its name says `review-required` and its metadata carries
  `comment="derived upscale, human review required"`, so a copy that leaves the work directory
  cannot pass for the master;
- it **refuses** when the master already has `ENHANCE_HEIGHT` lines (default 1080) or more, because
  an upscale of an upscale is pixels without detail.

Deleting `enhanced.review-required.mkv` loses nothing: it is reproducible from the master at any
time, and the master is the record.

### A frozen picture is reported, never silently archived

A VHS player that is paused, or that stalls, produces a still picture — the same thing as a still
shot in the content. `freeze` scans the cut with `freezedetect=n=0.003:d=2` and classes every span
by length:

| class    | length     | meaning                                                    |
| -------- | ---------- | ---------------------------------------------------------- |
| `freeze` | up to 10 s | a still shot in the content; normal, nothing to do         |
| `stuck`  | over 10 s  | a paused or stuck player; the operator must check the tape |

The span is never cut out: a tape that paused for a minute is still the tape. The scan runs on
`cut.mkv`, not on the source, because the black preamble is a static picture too and would be
reported as stuck. A capture that is `stuck` for more than a third of its content gets
`"suspect": true` in the report; the run still completes, but nobody may call the result a clean
archive without reading the flag.

## The archive report

`report` reads what every other stage wrote and puts it in one `report.json`, so "what is this tape"
is answerable without opening the work directory:

```json
{
  "capture": { "path": "…/vhs-synthetic-02.mkv", "seconds": 180.021, "width": 720, "height": 576 },
  "content": { "begin": 30.0, "end": 150.0, "seconds": 120.0, "broken": false },
  "black": {
    "spans": [
      { "start": 0.0, "end": 30.0, "seconds": 30.0 },
      { "start": 150.0, "end": 179.96, "seconds": 29.96 }
    ],
    "total_seconds": 59.96
  },
  "frozen": {
    "spans": [
      { "start": 45.0, "end": 60.0, "seconds": 15.0, "class": "stuck" },
      { "start": 100.0, "end": 105.0, "seconds": 5.0, "class": "freeze" }
    ],
    "stuck_seconds": 15.0,
    "freeze_seconds": 5.0,
    "stuck_ratio": 0.125
  },
  "transcript": { "path": "…/transcript.txt", "bytes": 158 },
  "master": {
    "path": "…/master.mkv",
    "bytes": 39848226,
    "seconds": 120.008,
    "width": 720,
    "height": 576,
    "codec": "av1",
    "pix_fmt": "yuv420p10le",
    "upscaled": false
  },
  "proxy": {
    "path": "…/proxy.mp4",
    "bytes": 17462957,
    "seconds": 120.0,
    "width": 720,
    "height": 576,
    "codec": "h264",
    "pix_fmt": "yuv420p"
  },
  "suspect": false
}
```

| field                  | source                            | meaning                                                           |
| ---------------------- | --------------------------------- | ----------------------------------------------------------------- |
| `capture`              | `probe.json`                      | the source as it arrived, and its own resolution                  |
| `content`              | `cut.json` (`cut.py --info`)      | the span the cut kept; `broken` when the tape had no content      |
| `black`                | `cut.json`                        | the black spans measured on the source, which the cut removed     |
| `frozen.spans[].class` | `frozen.json` (`freeze.py`)       | `freeze` for a still shot, `stuck` for a paused or stalled player |
| `frozen.stuck_ratio`   | `stuck_seconds / content.seconds` | above `1/3` the capture is `suspect`                              |
| `transcript`           | the `transcribe` stage            | where the text is, and how big; `0` bytes when there was no audio |
| `master`               | `ffprobe` of `master.mkv`         | size, resolution, codec; `upscaled` is the never-upscale check    |
| `proxy`                | `ffprobe` of `proxy.mp4`          | size and resolution of the client copy                            |
| `suspect`              | the rule above                    | the tape paused or stalled for more than a third of its content   |

`report` exits non-zero when the master is larger than the source. The report is written either way,
so a failure still leaves the evidence behind.

## Conventions

- **Sources are never modified.** Every output lands in `OUT`, a work directory beside the capture.
- **Atomic stages.** Each recipe writes `name.tmp.ext` and renames, so an interrupted run never
  leaves a file that looks complete.
- **Silent tapes are normal.** An empty `audio.wav` means "no audio", and the master is built
  video-only instead of failing.
- **Masters stay on the engine host**, `proxy.mp4` is the only file meant to be copied to a weaker
  client.
- **The archive never upscales.** Only `enhance` adds pixels, and it is tagged, optional and
  review-only; see [Two rules about the picture](#two-rules-about-the-picture).

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
