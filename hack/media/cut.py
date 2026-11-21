#!/usr/bin/env python3
"""Cut a capture down to its content.

A VHS recording starts when the cassette plays and ends when it stops; everything before and after
is black or snow. `blackdetect` finds those spans, and this keeps the content between the first and
the last one.

A capture that is black throughout is *not* an error: it is a broken or empty tape, and the tool
leaves the file whole and writes a `<out>.broken.json` marker so the caller can tag it instead of
guessing from a zero-length output.

The span it chose is what the archive report calls "content", so `--info` writes it beside the cut
as JSON: the span, the black spans it was derived from, and whether the tape was broken.

Usage: cut.py --src IN --probe probe.json --out OUT --ffmpeg ffmpeg [--threshold 0.10] [--min 0.6]
               [--marker PATH] [--info PATH]
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


def content_span(
    spans: list[tuple[float, float]], total: float, trailing_slack: float = 0.25
) -> tuple[float, float] | None:
    """The span that survives: from the end of the leading black to the start of the trailing black.

    Leading black always begins at frame zero, so a tight tolerance is safe there. Trailing black
    always runs to the end of the file, but `blackdetect` reports the start of the last black
    *frame*, so the span ends up to one frame short — plus whatever the container adds for the
    audio stream. `trailing_slack` covers that and nothing more.
    """
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
    if merged and merged[-1][1] >= total - trailing_slack:
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
    ap.add_argument(
        "--threshold",
        type=float,
        default=0.10,
        help="pixel brightness that counts as black",
    )
    ap.add_argument(
        "--min", type=float, default=0.6, help="seconds of black that count as a span"
    )
    ap.add_argument(
        "--marker", help="broken-tape marker path (default: OUT.broken.json)"
    )
    ap.add_argument("--info", help="write the chosen span and the black spans as JSON")
    args = ap.parse_args()

    total = duration(args.probe)
    spans = black_spans(args.ffmpeg, args.src, args.threshold, args.min)
    span = content_span(spans, total, max(0.25, 3 * frame_duration(args.probe)))

    if span is None:
        # Broken or empty tape: keep it whole, tag it, and let the caller decide.
        marker = args.marker or args.out + ".broken.json"
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
    if result.returncode != 0 or not args.info:
        return result.returncode

    # Only a cut that ffmpeg accepted gets a description; a half-written file must not look
    # measured. The black spans are the ones measured on the source, which is what the cut removed.
    info = {
        "source": args.src,
        "duration": round(total, 3),
        "begin": None,
        "end": None,
        "seconds": round(total, 3),
        "broken": span is None,
        "black_spans": [
            {"start": round(s, 3), "end": round(e, 3), "seconds": round(e - s, 3)}
            for s, e in spans
        ],
    }
    if span is not None:
        info["begin"] = round(span[0], 3)
        info["end"] = round(span[1], 3)
        info["seconds"] = round(span[1] - span[0], 3)
    with open(args.info, "w") as fh:
        json.dump(info, fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
