---
type: Research
description: End-to-end proof of the archive half of the media bench on brys with a synthetic capture — the regeneration recipe, the per-stage wall times, the verification output, and the three defects the run exposed.
task: definition.md
authored_by: agent
timestamp: 2026-11-21T18:45:00+01:00
---

# The VHS archive half, proven on a synthetic capture

The bench in `hack/media/` had only ever run on a tiny synthetic clip on the workstation. There is
no VHS player and no capture card, so this run replaced the missing hardware with a generated
stand-in and pushed the archive half through it on `brys`:

```
cut → transcribe → encode (deint → denoise → audio → master → proxy) → vmaf
```

Everything below is measured, not estimated. The capture and the work directory were deleted after
the run; only the numbers and the recipe remain.

## Result at a glance

| stage        | command                                        | wall    | product                                        |
| ------------ | ---------------------------------------------- | ------- | ---------------------------------------------- |
| capture      | `gen-capture.sh` (see below)                   | 3.86 s  | `incoming/vhs-synthetic-01.mkv`, 22.9 MiB      |
| `cut`        | `make cut`                                     | 4.31 s  | `cut.mkv`, 120.000 s, FFV1 + FLAC              |
| `deint`      | `make deint`                                   | 7.32 s  | `deinterlaced.mkv`, 324 MB, 50 fps             |
| `denoise`    | `make denoise`                                 | 7.26 s  | `video-denoised.mkv`, 327 MB                   |
| `audio`      | `make audio`                                   | 0.74 s  | `audio.wav`, `audio-clean.wav`, 11.5 MB each   |
| `transcribe` | `make transcribe`                              | 4.87 s  | `transcript.txt`, 146 B                        |
| `master`     | `make master`                                  | 23.11 s | `master.mkv`, AV1 10-bit + Opus, 45.2 MiB      |
| `proxy`      | `make proxy`                                   | 4.04 s  | `proxy.mp4`, H.264 8-bit, 19.7 MiB             |
| `vmaf`       | `make vmaf`                                    | 94.09 s | mean **96.90**, min 95.34, floor 93 → **pass** |
| —            | `make cut transcribe encode` (clean directory) | 73.40 s | the whole archive half in one command          |
| —            | the same command again                         | 0.01 s  | `Nothing to be done` for all three targets     |

The work directory held **834 MB** for two minutes of content. The host load average was 7.7 on 32
cores during the run, so the per-stage sum (51.7 s) and the single-command pass (73.4 s) differ by
about 40 %; the one-command number is the honest one.

## The synthetic capture

The stand-in is a PAL-sized progressive clip: **30 s black, 2 min of `testsrc2` with a burnt-in
timecode, 30 s black**, with an audio track that is silent except for one spoken sentence at 80 s.

```sh
#!/usr/bin/env bash
# Regenerate the synthetic VHS capture used by the archive PoC.
set -euo pipefail

FF=${FF:-ffmpeg}
PIPER=${PIPER:-piper}
VOICE=${VOICE:-/var/lib/kdn/llms/models/piper/en_US-lessac-medium.onnx}
IN=${IN:-/var/lib/kdn/media/incoming}
TMP=${TMP:-/var/lib/kdn/media/tmp}
OUT=${OUT:-$IN/vhs-synthetic-01.mkv}

# fontconfig wants a writable cache directory; without one it prints "No writable cache
# directories" on every drawtext frame.
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/var/lib/kdn/media/.cache}

mkdir -p "$IN" "$TMP" "$XDG_CACHE_HOME"

# The spoken sentence. It starts at 80 s, inside the content.
cat > "$TMP/script.txt" <<'TXT'
Archive test, take one. The media bench cuts the black from this recording and keeps two minutes of moving picture.
TXT
"$PIPER" --model "$VOICE" --input-file "$TMP/script.txt" -f "$TMP/speech.wav"

"$FF" -hide_banner -loglevel error -y \
  -f lavfi -i "color=c=black:s=720x576:r=25:d=30" \
  -f lavfi -i "testsrc2=s=720x576:r=25:d=120" \
  -f lavfi -i "color=c=black:s=720x576:r=25:d=30" \
  -f lavfi -t 180 -i "anullsrc=r=48000:cl=mono" \
  -i "$TMP/speech.wav" \
  -filter_complex "\
[0:v]format=yuv420p[b0];\
[1:v]drawtext=font=Noto Sans:text='SYNTHETIC CAPTURE %{pts\:hms}':x=(w-text_w)/2:y=h-80:fontsize=32:fontcolor=white:box=1:boxcolor=black@0.6,format=yuv420p[mid];\
[2:v]format=yuv420p[b1];\
[b0][mid][b1]concat=n=3:v=1:a=0[v];\
[4:a]aresample=48000,adelay=80000:all=1[sp];\
[3:a][sp]amix=inputs=2:duration=first:normalize=0[a]" \
  -map "[v]" -map "[a]" \
  -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -g 50 \
  -c:a aac -b:a 128k -ar 48000 \
  -metadata title="synthetic capture" \
  "$OUT"

echo "wrote $OUT"
```

`ffprobe` of the result:

```
duration=180.021000  size=24058355
video: h264 720x576 yuv420p 25/1
audio: aac 48000 Hz mono
```

`blackdetect` of the result, which is what `cut.py` sees:

```
black_start:0     black_end:30     black_duration:30
black_start:150   black_end:179.96 black_duration:29.96
```

Two choices in the recipe are deliberate. The timecode is burnt in, so a frame can be traced back to
a position in the tape. The audio is digital silence around the sentence, not tape hiss, so the
transcript check tests the chain and not the denoiser.

### Where the capture lives, and why that needed a mount

`brys` is impermanent: `/` is a **16 MiB tmpfs**, so `/var/lib/kdn/media` is not a place a capture
can land. The persistent trees are the ZFS datasets under `/var/lib/kdn/llms/*` and
`/var/tmp` (`brys-main/brys/impermanence/disposable`, 73 GB free). The run bound the disposable
dataset over the documented path, so the bench saw the real layout:

```sh
sudo mkdir -p /var/lib/kdn/media /var/tmp/kdn-media
sudo mount --bind /var/tmp/kdn-media /var/lib/kdn/media
```

A real deployment needs that path to be a dataset of its own, not a bind mount.

## Running the bench

`ffmpeg` and `ffprobe` are **not** in the host profile of `brys`, so the run took them from the
package set:

```sh
export PATH=$(nix shell nixpkgs#ffmpeg-full -c bash -c 'dirname $(command -v ffmpeg)'):$PATH
export SRC=/var/lib/kdn/media/incoming/vhs-synthetic-01.mkv
export OUT=/var/lib/kdn/media/work/vhs-synthetic-01
export WHISPER_MODEL=/var/lib/kdn/llms/models/whisper/ggml-base.en.bin

make -f hack/media/Makefile cut transcribe encode
make -f hack/media/Makefile vmaf
```

`ffmpeg-full` is the variant that carries both `libsvtav1` and `libvmaf`; plain `ffmpeg` from
nixpkgs has the encoder but not the VMAF filter. `whisper-cli` and `piper` are already in the host
profile.

The `cut` stage printed the span it chose:

```
cut: 180.0s -> 30.00..150.00 (120.0s)
```

## Verification

### The cut is the content and nothing else

`cut.mkv` is **120.000 s** — the two black minutes are gone and no content was lost. A second
`blackdetect` pass over the cut finds no black span at all, so the file starts and ends on picture:

```
=== black spans left in cut.mkv (want none)
(no black spans)
```

### The transcript contains the spoken sentence

```
[silence]
Archive test, take one.
The media bench cuts the black from this recording and keeps two minutes of moving picture.
[silence]
[silence]
```

Word for word. The `[silence]` markers are `whisper-cli` annotating the quiet spans, which is the
expected output for a mostly-silent track and not an artefact of the bench.

### The master is AV1 and the VMAF gate passes

```
master.mkv  120.008  av1,720,576,yuv420p10le,50/1  opus,48000,1
proxy.mp4   120.000  h264,720,576,yuv420p,50/1     aac,48000,1

vmaf: mean 96.90 harmonic 96.90 min 95.34 floor 93.0 -> pass
```

The 0.008 s of extra length is the Opus pre-skip. The proxy is 720x576 — the same size as the
master, not an upscale — and 8-bit, so consumer players decode it.

### The second run is a no-op

```
make: Nothing to be done for 'cut'.
make: Nothing to be done for 'transcribe'.
make: Nothing to be done for 'encode'.
### make cut transcribe encode rc=0 wall=0.00s
```

Every stage is a file target, so the whole bench is idempotent. `vmaf` is a phony target and always
re-measures, which is why it is a separate command and not part of `encode`.

## What the bench needed fixed

Three defects surfaced. Each needed a capture of this shape to appear: a black preamble, a black tail,
and SD resolution.

### 1. Trailing black was never trimmed — the cut came out 150 s, not 120 s

`cut.py` accepted a black span as the _trailing_ one only if it ended within 0.05 s of the container
duration. `blackdetect` reports the start of the last black **frame**, so a span that runs to the end
of the file is always short by one frame — 0.04 s at 25 fps — and the container adds a little more
for the audio stream. The measured gap here was 0.061 s, so the condition never fired and the cut
kept the trailing 30 s of black:

```
cut: 180.0s -> 30.00..180.02 (150.0s)      # before
cut: 180.0s -> 30.00..150.00 (120.0s)      # after
```

The fix derives the tolerance from the frame rate (`max(0.25, 3 × frame duration)`) and applies it
to the trailing edge only. The leading edge keeps the tight 0.05 s tolerance, because leading black
always starts at frame zero — loosening it would eat the first frames of a tape that fades up.

### 2. The broken-tape marker landed on the temporary name

The Makefile writes the cut to `cut.tmp.mkv` and renames it, and `cut.py` derived the marker as
`<out>.broken.json` — so a broken tape produced `cut.tmp.mkv.broken.json`, a name the rename never
touches and nothing reads. `cut.py` now takes `--marker`, and the Makefile passes
`$(CUT).broken.json`. Exercised with a ten-second all-black capture:

```
cut: no content found (10.0s black); tagged .../vhs-broken-01/cut.mkv.broken.json

-rw-r--r-- 13989 cut.mkv             # the whole 10.021 s, kept as-is
-rw-r--r--   107 cut.mkv.broken.json # {"reason": "no content span", "duration": 10.021, ...}
```

### 3. The proxy upscaled SD and kept 10-bit

`scale=-2:720` forces 720 **lines**, so a 576-line PAL master became a 900x720 proxy: larger than
the master it was meant to be a smaller copy of, and in `yuv420p10le` because the master is 10-bit.
Now `scale=-2:'min(720,ih)'` plus `-pix_fmt yuv420p` — 720x576 8-bit, 19.7 MiB against the master's
45.2 MiB.

## What changes with a real capture

Nothing in the stages. The stages are the same commands with the same flags; only the sizes and the
noise change.

- **A real tape is hours, not minutes.** At the measured throughput a two-hour capture needs
  **50 to 75 minutes of compute** — 60 × the 51.7 s per-stage sum, or 60 × the 73.4 s single-command
  pass, minus the VMAF sample, which is capped at 120 s and does not grow — and about **48 GB of
  intermediates** while it runs: 9 GB for `cut.mkv`, 19 GB for `deinterlaced.mkv`, 20 GB for
  `video-denoised.mkv`. The master is 2.8 GB and the proxy 1.2 GB. The intermediates are deletable
  as soon as the master exists; the bench never deletes them itself.
- **No timecode.** The burnt-in clock is a convenience of the stand-in. `blackdetect` and
  `whisper-cli` never read it. A real tape's only landmarks are the black at each end and the
  speech in between.
- **The audio is noisy, not silent.** Real tape hiss is broadband and the denoiser earns its place.
  On this capture `afftdn` had nothing to remove and the transcript came back word for word; on a
  real tape the transcript is the first thing that degrades, and `make transcribe` is where the
  whisper model size starts to matter.
- **Real PAL is interlaced.** `bwdif=mode=send_field` doubles 25 fields/s into 50 fps, which is
  correct for a 576i capture and is exactly why `deinterlaced.mkv` is the largest file in the work
  directory. This synthetic source is progressive, so the same filter doubles frames that were never
  interlaced: the `master` number above is pessimistic by about a factor of two in frame count. On a
  real 576i capture the doubling is the point, not a cost.
- **`make vmaf` samples, it does not sweep.** `vmaf.py` measures at most `--sample-seconds` (120 s)
  from the head of the master. On a two-hour tape that is a spot check of the opening minutes, not a
  guarantee for the whole file. It is the right default — a full VMAF sweep costs about as long as
  the encode — but a tape whose second half is much harder than its first will pass on the sample.

## Not proven here

- The `deepFilter` branch of the `audio` target. The CLI is not packaged (see
  [README](../../../../hack/media/README.md)), so the run took the `ffmpeg` branch.
- GPU admission. No stage of the archive half calls `admit`; `ADMIT` is unused by these targets.
- The restore-only stages beyond `encode`: nothing here tests an upscale or an interpolation step,
  because the bench has none yet.
