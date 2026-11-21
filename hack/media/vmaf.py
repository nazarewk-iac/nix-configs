#!/usr/bin/env python3
"""Gate an encode on VMAF.

The bench's promise is "compression without visible degradation", and a promise needs a number.
`libvmaf` scores the distorted file against the reference on a perceptual scale where 93+ is
transparent for archive purposes and below 90 shows in gradients and grain.

Usage: vmaf.py --reference REF --distorted ENC --floor 93 [--ffmpeg ffmpeg]
Exit: 0 above the floor, 1 below, 2 the measurement failed.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reference", required=True)
    ap.add_argument("--distorted", required=True)
    ap.add_argument("--floor", type=float, default=93.0)
    ap.add_argument("--ffmpeg", default="ffmpeg")
    ap.add_argument(
        "--sample-seconds", type=float, default=120.0, help="measure at most this much"
    )
    args = ap.parse_args()

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as fh:
        log_path = fh.name

    cmd = [
        args.ffmpeg,
        "-hide_banner",
        "-nostats",
        "-t",
        f"{args.sample_seconds}",
        "-i",
        args.distorted,
        "-t",
        f"{args.sample_seconds}",
        "-i",
        args.reference,
        "-lavfi",
        f"[0:v][1:v]libvmaf=log_fmt=json:log_path={log_path}",
        "-f",
        "null",
        "-",
    ]
    out = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    if out.returncode != 0:
        print(f"vmaf: ffmpeg failed: {out.stderr[-400:]}", file=sys.stderr)
        return 2

    try:
        with open(log_path) as fh:
            report = json.load(fh)
        pooled = report["pooled_metrics"]["vmaf"]
        mean = float(pooled["mean"])
        harmonic = float(pooled.get("harmonic_mean", mean))
        low = float(pooled.get("min", mean))
    except (OSError, KeyError, ValueError) as err:
        print(f"vmaf: cannot read the report: {err}", file=sys.stderr)
        return 2

    verdict = "pass" if mean >= args.floor else "FAIL"
    print(
        f"vmaf: mean {mean:.2f} harmonic {harmonic:.2f} min {low:.2f} floor {args.floor:.1f} -> {verdict}",
        file=sys.stderr,
    )
    return 0 if mean >= args.floor else 1


if __name__ == "__main__":
    sys.exit(main())
