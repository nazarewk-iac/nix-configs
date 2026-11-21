---
type: Research
description: End-to-end proof of the archive half of the media bench on brys with a synthetic capture — the regeneration recipe, the per-stage wall times, the archive report, the freeze detector and the tagged upscale, and the defects the run exposed.
task: definition.md
authored_by: agent
timestamp: 2026-11-21T19:20:00+01:00
---

# The VHS archive half, proven on a synthetic capture

The bench in `hack/media/` had only ever run on a tiny synthetic clip on the workstation. There is
no VHS player and no capture card, so this run replaced the missing hardware with a generated
stand-in and pushed the archive half through it on `brys`:

```
cut → freeze → transcribe → encode (deint → denoise → audio → master → proxy) → report → vmaf
```

Everything below is measured, not estimated. The captures and the work directories were deleted
after the run; only the numbers and the recipe remain.

## Result at a glance

| stage        | command                                    | wall    | product                                             |
| ------------ | ------------------------------------------ | ------- | --------------------------------------------------- |
| capture      | `gen-capture.sh` (see below)               | 11.5 s  | `vhs-synthetic-02.mkv`, 19.6 MiB                    |
| `cut`        | `make cut`                                 | 4.41 s  | `cut.mkv`, 120.000 s, FFV1 + FLAC, 135.9 MiB        |
| `freeze`     | `make freeze`                              | 1.72 s  | `frozen.json`, 2 spans: 15 s `stuck`, 5 s `freeze`  |
| `deint`      | `make deint`                               | 7.15 s  | `deinterlaced.mkv`, 287.1 MiB, 50 fps               |
| `denoise`    | `make denoise`                             | 7.83 s  | `video-denoised.mkv`, 288.1 MiB                     |
| `audio`      | `make audio`                               | 0.74 s  | `audio.wav`, `audio-clean.wav`, 11.0 MiB each       |
| `transcribe` | `make transcribe`                          | 5.01 s  | `transcript.txt`, 158 B                             |
| `master`     | `make master`                              | 23.24 s | `master.mkv`, AV1 10-bit + Opus, 38.0 MiB, 576p     |
| `proxy`      | `make proxy`                               | 3.85 s  | `proxy.mp4`, H.264 8-bit, 16.7 MiB, 576p            |
| `report`     | `make report`                              | 0.25 s  | `report.json`, 1413 B                               |
| `vmaf`       | `make vmaf`                                | 87.93 s | mean **96.94**, min 95.23, floor 93 → **pass**      |
| `enhance`    | `make enhance`                             | 21.3 s  | `enhanced.review-required.mkv`, 1350x1080, 90.4 MiB |
| —            | `make cut freeze transcribe encode report` | 57.13 s | the whole archive half in one command               |
| —            | the same command again                     | 0.00 s  | `Nothing to be done` for all five targets           |

The per-stage sum without `vmaf` is 54.2 s and the single command took 57.13 s, so the two agree to
within 5 %; the load average was 13.59 on 32 cores during the run, and the one-command number is the
honest one. The work directory held **858 MB** for two minutes of content, or 768 MB without the
`enhance` derivative.

## The synthetic capture

Two captures, both PAL-sized progressive clips with a silent track around one spoken sentence.

`vhs-synthetic-02.mkv` is the main one: **30 s black, 45 s moving, 15 s frozen, 40 s moving, 5 s
still, 15 s moving, 30 s black** — 180 s in total, 120 s of content, with the sentence at 110 s. The
15 s frozen span is the paused player the freeze detector must find; the 5 s still is the ordinary
still shot that must be classed differently.

`vhs-stuck-01.mkv` is the suspect case: **30 s black, 10 s moving, 70 s frozen, 10 s moving, 30 s
black** — 90 s of content with 70 s stuck, which is 78 % and over the one-third line.

```sh
#!/usr/bin/env bash
# Regenerate the synthetic VHS captures used by the archive PoC.
#
#   vhs-synthetic-02.mkv  180 s: 30 s black, 45 s moving, 15 s FROZEN, 40 s moving, 5 s still,
#                         15 s moving, 30 s black. Content 120 s, frozen 20 s (15 s stuck + 5 s
#                         still), speech at 110 s.
#   vhs-stuck-01.mkv      150 s: 30 s black, 10 s moving, 70 s FROZEN, 10 s moving, 30 s black.
#                         Content 90 s, stuck 70 s -> 78 %, the suspect case. Silent.
set -euo pipefail

FF=${FF:-ffmpeg}
PIPER=${PIPER:-piper}
VOICE=${VOICE:-/var/lib/kdn/llms/models/piper/en_US-lessac-medium.onnx}
IN=${IN:-/var/lib/kdn/media/incoming}
TMP=${TMP:-/var/lib/kdn/media/tmp}

# fontconfig wants a writable cache directory; without one it prints "No writable cache
# directories" on every drawtext frame.
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/var/lib/kdn/media/.cache}
mkdir -p "$IN" "$TMP" "$XDG_CACHE_HOME"

# The spoken sentence.
cat > "$TMP/script.txt" <<'TXT'
Archive test, take one. The media bench cuts the black from this recording and keeps two minutes of moving picture.
TXT
"$PIPER" --model "$VOICE" --input-file "$TMP/script.txt" -f "$TMP/speech.wav"

# A held frame: one frame of the test pattern with a label, so a human can see the frozen span. The
# label is static, so the picture really is frozen; a burnt-in clock would move and defeat the test.
"$FF" -hide_banner -loglevel error -y -f lavfi -i "testsrc2=s=720x576:r=25:d=1" \
  -vf "select=eq(n\,12),drawtext=font=Noto Sans:text='PAUSED':x=(w-text_w)/2:y=(h-text_h)/2:fontsize=64:fontcolor=white:box=1:boxcolor=black@0.7,format=yuv420p" \
  -frames:v 1 "$TMP/still.png"

TC="drawtext=font=Noto Sans:text='SYNTHETIC %{pts\:hms}':x=(w-text_w)/2:y=h-80:fontsize=32:fontcolor=white:box=1:boxcolor=black@0.6,format=yuv420p"

# --- the main capture: 15 s frozen span plus a 5 s still shot, both inside the content ----------
"$FF" -hide_banner -loglevel error -y \
  -f lavfi -i "color=c=black:s=720x576:r=25:d=30" \
  -f lavfi -i "testsrc2=s=720x576:r=25:d=45" \
  -loop 1 -framerate 25 -t 15 -i "$TMP/still.png" \
  -f lavfi -i "testsrc2=s=720x576:r=25:d=40" \
  -loop 1 -framerate 25 -t 5 -i "$TMP/still.png" \
  -f lavfi -i "testsrc2=s=720x576:r=25:d=15" \
  -f lavfi -i "color=c=black:s=720x576:r=25:d=30" \
  -filter_complex "\
[0:v]format=yuv420p[s0];\
[1:v]$TC[m1];\
[2:v]format=yuv420p[f1];\
[3:v]$TC[m2];\
[4:v]format=yuv420p[f2];\
[5:v]$TC[m3];\
[6:v]format=yuv420p[s1];\
[s0][m1][f1][m2][f2][m3][s1]concat=n=7:v=1:a=0[v]" \
  -map "[v]" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -g 50 -an \
  "$TMP/synthetic-02-video.mkv"

"$FF" -hide_banner -loglevel error -y \
  -f lavfi -t 180 -i "anullsrc=r=48000:cl=mono" -i "$TMP/speech.wav" \
  -filter_complex "[1:a]aresample=48000,adelay=110000:all=1[sp];\
[0:a][sp]amix=inputs=2:duration=first:normalize=0[a]" \
  -map "[a]" -c:a aac -b:a 128k -ar 48000 "$TMP/synthetic-02-audio.m4a"

"$FF" -hide_banner -loglevel error -y -i "$TMP/synthetic-02-video.mkv" \
  -i "$TMP/synthetic-02-audio.m4a" -map 0:v:0 -map 1:a:0 -c copy \
  -metadata title="synthetic capture" "$IN/vhs-synthetic-02.mkv"

# --- the stuck capture: one 70 s frozen span in 90 s of content -> suspect ----------------------
"$FF" -hide_banner -loglevel error -y \
  -f lavfi -i "color=c=black:s=720x576:r=25:d=30" \
  -f lavfi -i "testsrc2=s=720x576:r=25:d=10" \
  -loop 1 -framerate 25 -t 70 -i "$TMP/still.png" \
  -f lavfi -i "testsrc2=s=720x576:r=25:d=10" \
  -f lavfi -i "color=c=black:s=720x576:r=25:d=30" \
  -f lavfi -t 150 -i "anullsrc=r=48000:cl=mono" \
  -filter_complex "\
[0:v]format=yuv420p[s0];\
[1:v]$TC[m1];\
[2:v]format=yuv420p[f1];\
[3:v]$TC[m2];\
[4:v]format=yuv420p[s1];\
[s0][m1][f1][m2][s1]concat=n=5:v=1:a=0[v]" \
  -map "[v]" -map 5:a -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -g 50 \
  -c:a aac -b:a 128k -ar 48000 -metadata title="stuck capture" "$IN/vhs-stuck-01.mkv"

echo "wrote $IN/vhs-synthetic-02.mkv and $IN/vhs-stuck-01.mkv"
```

`ffprobe` of the main capture:

```
duration=180.021000  size=20506337
video: h264 720x576 yuv420p 25/1
audio: aac 48000 Hz mono
```

Two choices in the recipe are deliberate. The timecode is burnt in, so a frame can be traced back to
a position in the tape — but only on the moving segments: a clock drawn over the held frame would
change pixels every frame and the picture would not be frozen. The audio is digital silence around
the sentence, not tape hiss, so the transcript check tests the chain and not the denoiser.

### Where the captures live, and why that needed a mount

`brys` is impermanent: `/` is a **16 MiB tmpfs**, so `/var/lib/kdn/media` is not a place a capture
can land. The persistent trees are the ZFS datasets under `/var/lib/kdn/llms/*` and `/var/tmp`
(`brys-main/brys/impermanence/disposable`, 73 GB free). The run bound the disposable dataset over
the documented path, so the bench saw the real layout:

```sh
sudo mkdir -p /var/lib/kdn/media /var/tmp/kdn-media
sudo mount --bind /var/tmp/kdn-media /var/lib/kdn/media
```

The directory is root-owned after the mount, so the run also needs
`sudo chown kdn:users /var/tmp/kdn-media` before anything can be written. A real deployment needs
that path to be a dataset of its own, not a bind mount.

## Running the bench

`ffmpeg` and `ffprobe` are **not** in the host profile of `brys`, so the run took them from the
package set:

```sh
export PATH=$(nix shell nixpkgs#ffmpeg-full -c bash -c 'dirname $(command -v ffmpeg)'):$PATH
export SRC=/var/lib/kdn/media/incoming/vhs-synthetic-02.mkv
export OUT=/var/lib/kdn/media/work/vhs-synthetic-02
export WHISPER_MODEL=/var/lib/kdn/llms/models/whisper/ggml-base.en.bin

make -f hack/media/Makefile cut freeze transcribe encode report
make -f hack/media/Makefile vmaf
```

`ffmpeg-full` is the variant that carries both `libsvtav1` and `libvmaf`; plain `ffmpeg` from
nixpkgs has the encoder but not the VMAF filter. `whisper-cli` and `piper` are already in the host
profile. `freezedetect` and `blackdetect` are in every build.

The `cut` and `freeze` stages printed the spans they chose:

```
cut: 180.0s -> 30.00..150.00 (120.0s)
freeze: STUCK 45.00..60.00 (15.0s) — longer than 10s: the player paused or stalled; check the tape
freeze: still shot 100.00..105.00 (5.0s)
```

## Verification

### The cut is the content and nothing else

`cut.mkv` is **120.000 s** — the two black minutes are gone and no content was lost. A second
`blackdetect` pass over the cut finds no black span at all, so the file starts and ends on picture.
`cut.json` records what the cut removed:

```json
{
  "source": "/var/lib/kdn/media/incoming/vhs-synthetic-02.mkv",
  "duration": 180.021,
  "begin": 30.0,
  "end": 150.0,
  "seconds": 120.0,
  "broken": false,
  "black_spans": [
    { "start": 0.0, "end": 30.0, "seconds": 30.0 },
    { "start": 150.0, "end": 179.96, "seconds": 29.96 }
  ]
}
```

### The freeze detector finds the paused player and names it

`frozen.json` from the main capture:

```json
{
  "source": "/var/lib/kdn/media/work/vhs-synthetic-02/cut.mkv",
  "parameters": { "noise": 0.003, "min_seconds": 2.0, "stuck_seconds": 10.0 },
  "spans": [
    { "start": 45.0, "end": 60.0, "seconds": 15.0, "class": "stuck" },
    { "start": 100.0, "end": 105.0, "seconds": 5.0, "class": "freeze" }
  ],
  "stuck_seconds": 15.0,
  "freeze_seconds": 5.0
}
```

Both classes appear, in the order they occur, and the 15 s hold is classed `stuck` while the 5 s
hold is classed `freeze`. **The scan runs on the cut, not on the source**, and that is not a
detail. `freezedetect` cannot tell a still picture from black — black is a static picture too — so a
scan of the source reports the black preamble and the black tail as stuck:

```
# on the source
freeze: STUCK 0.00..30.00 (30.0s)     ← the black preamble
freeze: STUCK 75.00..90.00 (15.0s)    ← the real one
freeze: still shot 130.00..135.00 (5.0s)
freeze: STUCK 150.00..180.02 (30.0s)  ← the black tail

# on the cut
freeze: STUCK 45.00..60.00 (15.0s)
freeze: still shot 100.00..105.00 (5.0s)
```

A detector that cries "stuck" on every tape with a black preamble would be ignored within a week.

### The archive report

`report.json` for the main capture, verbatim:

```json
{
  "capture": {
    "path": "/var/lib/kdn/media/incoming/vhs-synthetic-02.mkv",
    "seconds": 180.021,
    "width": 720,
    "height": 576
  },
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
  "transcript": {
    "path": "/var/lib/kdn/media/work/vhs-synthetic-02/transcript.txt",
    "bytes": 158
  },
  "master": {
    "path": "/var/lib/kdn/media/work/vhs-synthetic-02/master.mkv",
    "bytes": 39848226,
    "seconds": 120.008,
    "width": 720,
    "height": 576,
    "codec": "av1",
    "pix_fmt": "yuv420p10le",
    "upscaled": false
  },
  "proxy": {
    "path": "/var/lib/kdn/media/work/vhs-synthetic-02/proxy.mp4",
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

`stuck_ratio` is 15 s of 120 s = 0.125, below one third, so `suspect` is `false`. The same report for
the stuck capture:

```json
{
  "content": { "begin": 30.0, "end": 120.0, "seconds": 90.0, "broken": false },
  "frozen": {
    "spans": [{ "start": 10.0, "end": 80.0, "seconds": 70.0, "class": "stuck" }],
    "stuck_seconds": 70.0,
    "freeze_seconds": 0.0,
    "stuck_ratio": 0.7778
  },
  "master": { "width": 720, "height": 576, "upscaled": false },
  "transcript": { "bytes": 12 },
  "suspect": true
}
```

and the stage says so on stderr, in words an operator can act on:

```
report: 90.0s content, 2 black span(s), 1 frozen span(s) (70.0s stuck, 0.0s still), master 720x576 8.2 MiB, proxy 3.8 MiB, SUSPECT
report: stuck 10.00..80.00 (70.0s) — check the tape
report: SUSPECT — stuck for 78% of the content, more than a third; the player paused or stalled
```

The run still exits 0: a paused player is a fact about the tape, not an error, and the recording is
still worth archiving. What must not happen is a clean report.

### The transcript contains the spoken sentence

```
[BLANK_AUDIO]
[BLANK_AUDIO]
Archive test, take one.
The media bench cuts the black from this recording and
keeps two minutes of moving picture.
[BLANK_AUDIO]
```

Word for word. The `[BLANK_AUDIO]` markers are `whisper-cli` annotating the quiet spans, which is
the expected output for a mostly-silent track and not an artefact of the bench.

### The master is AV1, at 576 lines, and the VMAF gate passes

```
master.mkv  120.008  av1,720,576,yuv420p10le,50/1  opus,48000,1
proxy.mp4   120.000  h264,720,576,yuv420p,50/1    aac,48000,1

vmaf: mean 96.94 harmonic 96.94 min 95.23 floor 93.0 -> pass
```

The master is **720x576 — the capture's own resolution**, not one line more. The 0.008 s of extra
length is the Opus pre-skip. The proxy is 720x576 as well: the `min(720,ih)` cap keeps it at the
master's height instead of upscaling it, and 8-bit is what consumer players decode.

### The upscale is tagged, and refuses when there is nothing to upscale

`make enhance` is not part of `all` and nothing depends on it. Asked for explicitly, it produced:

```
enhance: 576 -> 1080 lines, derived and tagged; NOT part of the archive
enhanced.review-required.mkv   h264,1350,1080,yuv420p,50/1   90.4 MiB   21.3 s

tags: title=vhs-synthetic-02 (derived upscale, human review required)
      COMMENT=derived upscale, human review required
```

1350x1080 from a 720x576 master: 2.25x the pixels, from the same detail. The filename and both
metadata fields say what it is, so it cannot pass for the master if it is copied out of the work
directory. Deleting it loses nothing — the master is the record.

At or above the target height it refuses, and it refuses on every run, not only the first:

```
$ make enhance ENHANCE_HEIGHT=576
enhance: refused: the master is 576 lines, at or above ENHANCE_HEIGHT=576.
enhance: an upscale adds pixels, not detail; the archive stays at 576.
make: *** [hack/media/Makefile:211: enhance-guard] Error 1
```

`make` reports exit 2 for a failed recipe; the derivative on disk is untouched.

### The second run is a no-op

```
make: Nothing to be done for 'cut'.
make: Nothing to be done for 'freeze'.
make: Nothing to be done for 'transcribe'.
make: Nothing to be done for 'encode'.
make: Nothing to be done for 'report'.
### second run rc=0 wall=0.00s
```

Every stage is a file target, so the whole bench is idempotent. `vmaf` is a phony target and always
re-measures, which is why it is a separate command and not part of `encode`. `enhance` is the one
deliberate exception: its guard is a phony prerequisite, so the height check runs every time it is
asked for, even when an older derivative is still on disk.

## What the bench needed fixed

Five defects surfaced. Three needed a capture of this shape — a black preamble, a black tail, SD
resolution, a held picture — and two needed the new stages to be exercised rather than read.

### 1. A frozen span that ran to the end of the file came out zero seconds long

`freezedetect` logs `freeze_start`, then `freeze_duration` and `freeze_end` when the picture moves
again. A file that ends while still frozen logs **only the start** — no duration, no end:

```
freezedetect.freeze_start: 150
                        ← nothing else, the file ended
```

The first version of `freeze.py` closed such a span with its own duration, which it did not have, so
the span came out as `150..150` and was classed `freeze`. A tape whose player stalled at the end
would have been reported as "no problem". The span now closes at the file duration from `ffprobe`
when ffmpeg gives no duration, and the source scan above shows it working
(`150.00..180.02 (30.0s)`).

### 2. Matroska silently dropped the `comment` tag on the derivative

`-metadata comment="derived upscale, human review required"` produced a file with no comment at all:

```
$ ffprobe ... enhanced.review-required.mkv
tags: title=vhs-synthetic-02 (derived upscale, human review required) comment=null
```

The Matroska muxer keeps the uppercase key and drops the lowercase one. Measured on `brys`:

```
$ ffmpeg -f lavfi -i testsrc2 -metadata title=T -metadata comment=C -metadata COMMENT=C2 t.mkv
format tags: { "title": "T", "COMMENT": "C2", "ENCODER": "Lavf63.1.102" }
```

`C` is gone and `C2` survived. The Makefile now writes `COMMENT`, and the filename still carries
`review-required` — two independent tags, because the one that disappeared did so without a message.

### 3. The `enhance` refusal was skipped when an older derivative existed

`enhance` was a plain file target. Make sees `enhanced.review-required.mkv` newer than `master.mkv`
and answers `Nothing to be done` — the height check never runs, and a second `make enhance` after a
`ENHANCE_HEIGHT` change silently keeps the old file. The check is now a phony prerequisite
(`enhance-guard`), so it runs on every request and the recipe follows it only when it passes.

### 4. `make clean` was declared and did nothing

`clean` sat in `.PHONY` with no recipe, so make created an empty target:

```
$ make clean
make: Nothing to be done for 'clean'.
```

A person who ran it believed the intermediates were gone and the disk was still full. `clean` now
removes `deinterlaced.mkv`, `video-denoised.mkv`, `audio.wav` and `audio-clean.wav` and keeps the
master, the proxy, the report and the transcript.

### 5. Trailing black was never trimmed — the cut came out 150 s, not 120 s

Found in the earlier run and still worth recording, because it is the defect that needed this
capture shape. `cut.py` accepted a black span as the _trailing_ one only if it ended within 0.05 s
of the container duration. `blackdetect` reports the start of the last black **frame**, so a span
that runs to the end of the file is always short by one frame — 0.04 s at 25 fps — and the container
adds a little more for the audio stream. The measured gap here was 0.061 s, so the condition never
fired and the cut kept the trailing 30 s of black:

```
cut: 180.0s -> 30.00..180.02 (150.0s)      # before
cut: 180.0s -> 30.00..150.00 (120.0s)      # after
```

The fix derives the tolerance from the frame rate (`max(0.25, 3 × frame duration)`) and applies it
to the trailing edge only. The leading edge keeps the tight 0.05 s tolerance, because leading black
always starts at frame zero — loosening it would eat the first frames of a tape that fades up.

## What changes with a real capture

Nothing in the stages. The stages are the same commands with the same flags; only the sizes, the
noise and the number of frozen spans change.

- **A real tape is hours, not minutes.** At the measured throughput a two-hour capture needs
  **about an hour of compute** — 60 × the 57.13 s single-command pass, plus the VMAF sample, which
  is capped at 120 s and does not grow — and about **42 GiB of intermediates** while it runs: 8 GiB
  for `cut.mkv`, 16.8 GiB for `deinterlaced.mkv`, 16.9 GiB for `video-denoised.mkv`. The master is
  2.2 GiB and the proxy 1.0 GiB. The intermediates are deletable as soon as the master exists
  (`make clean`), and the bench never deletes them itself. These sizes are a **lower bound**: 20 of
  the 120 content seconds here are a held picture, which costs almost nothing to store, and a real
  tape has none.
- **No timecode.** The burnt-in clock is a convenience of the stand-in. `blackdetect`,
  `freezedetect` and `whisper-cli` never read it. A real tape's only landmarks are the black at each
  end, the speech in between, and whatever the freeze detector finds.
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
- **Ten seconds is a judgement, not a measurement.** `STUCK_SECONDS=10` separates a still shot from
  a paused player on the reasoning that no shot in a home recording holds perfectly still for ten
  seconds. A tape of a slideshow or a still-life subject will produce `stuck` spans that are not
  stuck; the class is a request to look, not a verdict. It is a make variable for exactly that
  reason.
- **A real stuck tape is usually stuck at the end.** The player pauses, the operator notices later,
  and the rest of the tape is one long hold. That is the case defect 1 was about, and it is why the
  end-of-file span closes on the file duration.

## Not proven here

- The `deepFilter` branch of the `audio` target. The CLI is not packaged (see
  [README](../../../../hack/media/README.md)), so the run took the `ffmpeg` branch.
- GPU admission. No stage of the archive half calls `admit`; `ADMIT` is unused by these targets.
- Anything about the picture quality of `enhance`. It was proven to be tagged, reviewable and
  refusal-capable, not to be better than the master — that is what the human review is for.
- The restore-only stages beyond `encode`: nothing here tests an upscale or an interpolation step
  beyond `enhance`, which is a review derivative and not a restoration.
