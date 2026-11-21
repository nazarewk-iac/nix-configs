#!/usr/bin/env python3
"""Classify the frozen spans of a capture: a still shot, or a stuck player.

`freezedetect` reports every span whose consecutive frames differ by less than `n`. It cannot tell
a still shot from a paused player, because both are one picture held and the filter sees the same
thing. Duration is the only difference that matters, so this classifies by length: a span longer
than `--stuck` seconds is `stuck` (the operator must check the tape), anything shorter is `freeze`
(a normal still shot).

The stage never fails the run and never cuts the span out. A paused player is still content, and a
player that paused for an hour is a fact about the tape that the report must carry, not a reason to
throw the recording away.

The scan runs on `cut.mkv`, not on the source: the black preamble of a capture is also a static
picture, so a scan of the source would report the leading black as a frozen span and call it stuck.
The cut has no black at its ends, which is what makes "frozen" mean "frozen picture".

Usage: freeze.py --src cut.mkv --out frozen.json [--ffmpeg ffmpeg] [--ffprobe ffprobe]
                 [--noise 0.003] [--min 2] [--stuck 10]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys


def spans(
    ffmpeg: str, ffprobe: str, src: str, noise: float, minimum: float
) -> list[tuple[float, float]]:
    """Return the frozen intervals as (start, end) in seconds.

    The filter logs three events, and their order is not guaranteed: `freeze_start`, then
    `freeze_duration` and `freeze_end` when the picture moves again. A file that ends while frozen
    emits the start and nothing else, so that span is closed with the file duration.
    """
    out = subprocess.run(
        [
            ffmpeg,
            "-hide_banner",
            "-nostats",
            "-i",
            src,
            "-vf",
            f"freezedetect=n={noise}:d={minimum}",
            "-an",
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
        errors="replace",
    )
    found: list[tuple[float, float]] = []
    start = None
    held = 0.0
    for line in out.stderr.splitlines():
        m = re.search(r"freeze_start:\s*([0-9.]+)", line)
        if m:
            start, held = float(m.group(1)), 0.0
            continue
        m = re.search(r"freeze_duration:\s*([0-9.]+)", line)
        if m:
            held = float(m.group(1))
            continue
        m = re.search(r"freeze_end:\s*([0-9.]+)", line)
        if m and start is not None:
            found.append((start, float(m.group(1))))
            start, held = None, 0.0
    if start is not None:
        # A span that runs to the end of the file has no end event, and ffmpeg does not always log a
        # duration for it either. Its own duration is the best answer when there is one; otherwise
        # the file duration is where the picture stopped moving.
        end = start + held if held > 0 else file_duration(ffprobe, src)
        found.append((start, max(start, end)))
    return found


def file_duration(ffprobe: str, path: str) -> float:
    """Seconds of the whole file, or 0 when ffprobe cannot say."""
    out = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "csv=p=0",
            path,
        ],
        capture_output=True,
        text=True,
        errors="replace",
    )
    try:
        return float(out.stdout.strip().splitlines()[0])
    except (IndexError, ValueError):
        return 0.0


def classify(seconds: float, stuck: float) -> str:
    """A long hold is a stuck player; a short one is a still shot in the content."""
    return "stuck" if seconds > stuck else "freeze"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--ffmpeg", default="ffmpeg")
    ap.add_argument("--ffprobe", default="ffprobe")
    ap.add_argument(
        "--noise",
        type=float,
        default=0.003,
        help="frame difference below this counts as unchanged (freezedetect n)",
    )
    ap.add_argument(
        "--min",
        type=float,
        default=2.0,
        help="seconds of no change before a span starts",
    )
    ap.add_argument(
        "--stuck",
        type=float,
        default=10.0,
        help="a span longer than this is a stuck player, not a still shot",
    )
    args = ap.parse_args()

    found = spans(args.ffmpeg, args.ffprobe, args.src, args.noise, args.min)
    report = {
        "source": args.src,
        "parameters": {
            "noise": args.noise,
            "min_seconds": args.min,
            "stuck_seconds": args.stuck,
        },
        "spans": [
            {
                "start": round(begin, 3),
                "end": round(end, 3),
                "seconds": round(end - begin, 3),
                "class": classify(end - begin, args.stuck),
            }
            for begin, end in found
        ],
        "stuck_seconds": round(
            float(
                sum(e - b for b, e in found if classify(e - b, args.stuck) == "stuck")
            ),
            3,
        ),
        "freeze_seconds": round(
            float(
                sum(e - b for b, e in found if classify(e - b, args.stuck) == "freeze")
            ),
            3,
        ),
    }

    with open(args.out, "w") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")

    for span in report["spans"]:
        where = f"{span['start']:.2f}..{span['end']:.2f} ({span['seconds']:.1f}s)"
        if span["class"] == "stuck":
            print(
                f"freeze: STUCK {where} — longer than {args.stuck:.0f}s: the player paused or "
                f"stalled; check the tape",
                file=sys.stderr,
            )
        else:
            print(f"freeze: still shot {where}", file=sys.stderr)
    if not report["spans"]:
        print("freeze: no frozen span", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
