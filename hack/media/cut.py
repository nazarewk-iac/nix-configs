#!/usr/bin/env python3
"""Cut a capture down to its content.

A VHS recording starts when the cassette plays and ends when it stops; everything before and after
is black or snow. `blackdetect` finds those spans, and this keeps the content between the first and
the last one.

A capture that is black throughout is *not* an error: it is a broken or empty tape, and the tool
leaves the file whole and writes a `<out>.broken.json` marker so the caller can tag it instead of
guessing from a zero-length output.

Usage: cut.py --src IN --probe probe.json --out OUT --ffmpeg ffmpeg [--threshold 0.10] [--min 0.6]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys


def duration(probe_path: str) -> float:
    with open(probe_path) as fh:
        return float(json.load(fh)["format"]["duration"])


def black_spans(
    ffmpeg: str, src: str, threshold: float, minimum: float
) -> list[tuple[float, float]]:
    """Return the black intervals as (start, end) in seconds."""
    out = subprocess.run(
        [
            ffmpeg,
            "-hide_banner",
            "-nostats",
            "-i",
            src,
            "-vf",
            f"blackdetect=d={minimum}:pix_th={threshold}",
            "-an",
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
        errors="replace",
    )
    spans: list[tuple[float, float]] = []
    start = None
    for line in out.stderr.splitlines():
        if "black_start:" in line:
            m = re.search(r"black_start:([0-9.]+)", line)
            if m:
                start = float(m.group(1))
        if "black_end:" in line and start is not None:
            m = re.search(r"black_end:([0-9.]+)", line)
            if m:
                spans.append((start, float(m.group(1))))
                start = None
    return spans


def content_span(spans: list[tuple[float, float]], total: float) -> tuple[float, float] | None:
    """The span that survives: from the end of the leading black to the start of the trailing black."""
    begin, end = 0.0, total
    # Merge overlapping or touching spans first, so a flicker does not split the tape.
    merged: list[list[float]] = []
    for s, e in sorted(spans):
        if merged and s <= merged[-1][1] + 0.05:
            merged[-1][1] = max(merged[-1][1], e)
        else:
            merged.append([s, e])
    if merged and merged[0][0] <= 0.05:
        begin = merged[0][1]
    if merged and merged[-1][1] >= total - 0.05:
        end = merged[-1][0]
    if end - begin < 1.0:
        return None
    return begin, end


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--probe", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--ffmpeg", default="ffmpeg")
    ap.add_argument("--threshold", type=float, default=0.10, help="pixel brightness that counts as black")
    ap.add_argument("--min", type=float, default=0.6, help="seconds of black that count as a span")
    args = ap.parse_args()

    total = duration(args.probe)
    spans = black_spans(args.ffmpeg, args.src, args.threshold, args.min)
    span = content_span(spans, total)

    if span is None:
        # Broken or empty tape: keep it whole, tag it, and let the caller decide.
        marker = args.out + ".broken.json"
        with open(marker, "w") as fh:
            json.dump(
                {"reason": "no content span", "duration": total, "black": spans},
                fh,
                indent=2,
            )
        print(
            f"cut: no content found ({total:.1f}s black); tagged {marker}",
            file=sys.stderr,
        )
        cmd = [
            args.ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            args.src,
            "-c",
            "copy",
            args.out,
        ]
    else:
        begin, end = span
        print(
            f"cut: {total:.1f}s -> {begin:.2f}..{end:.2f} ({end - begin:.1f}s)",
            file=sys.stderr,
        )
        cmd = [
            args.ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-ss",
            f"{begin:.3f}",
            "-to",
            f"{end:.3f}",
            "-i",
            args.src,
            "-c:v",
            "ffv1",
            "-level",
            "3",
            "-c:a",
            "flac",
            args.out,
        ]
    result = subprocess.run(cmd)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
