#!/usr/bin/env python3
"""Assemble the archive report for one capture.

Every stage leaves a file behind and this one reads them all: the cut span and the black spans from
`cut.py`, the frozen spans and their class from `freeze.py`, the transcript, and the size and
resolution of the master and the proxy. One JSON file answers "what is this tape" without opening
the work directory.

Two rules are checked here, because a report is the last place that can still refuse:

* the master must not be larger than the source. Archiving never upscales, and a master with more
  pixels than the capture is a bench defect, so the report says so and the stage fails.
* a capture that is `stuck` for more than a third of its content is flagged `suspect`. The run is
  not aborted — a paused player is a fact about the tape, not an error — but nobody may call the
  result a clean archive without reading the flag.

Usage: report.py --out report.json --probe probe.json --cut-json cut.json
                 --frozen-json frozen.json --transcript transcript.txt
                 --master master.mkv --proxy proxy.mp4 [--ffprobe ffprobe]
Exit: 0 the report is clean, 1 the master is upscaled, 2 an input could not be read.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

SUSPECT_RATIO = 1.0 / 3.0


def read_json(path: str) -> dict:
    with open(path) as fh:
        return json.load(fh)


def video_stream(ffprobe: str, path: str) -> dict:
    """The first video stream of a media file, with the format duration and size."""
    out = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            path,
        ],
        capture_output=True,
        text=True,
        errors="replace",
    )
    if out.returncode != 0:
        raise RuntimeError(f"ffprobe {path}: {out.stderr.strip()[-200:]}")
    probe = json.loads(out.stdout)
    stream = next(
        (s for s in probe.get("streams", []) if s.get("codec_type") == "video"), {}
    )
    return {
        "path": path,
        "bytes": int(probe.get("format", {}).get("size") or os.path.getsize(path)),
        "seconds": round(float(probe.get("format", {}).get("duration") or 0.0), 3),
        "width": int(stream.get("width") or 0),
        "height": int(stream.get("height") or 0),
        "codec": stream.get("codec_name"),
        "pix_fmt": stream.get("pix_fmt"),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--probe", required=True, help="probe.json of the source capture")
    ap.add_argument("--cut-json", required=True, help="cut.json written by cut.py")
    ap.add_argument(
        "--frozen-json", required=True, help="frozen.json written by freeze.py"
    )
    ap.add_argument("--transcript", required=True)
    ap.add_argument("--master", required=True)
    ap.add_argument("--proxy", required=True)
    ap.add_argument("--ffprobe", default="ffprobe")
    args = ap.parse_args()

    try:
        source_probe = read_json(args.probe)
        cut = read_json(args.cut_json)
        frozen = read_json(args.frozen_json)
        master = video_stream(args.ffprobe, args.master)
        proxy = video_stream(args.ffprobe, args.proxy)
    except (OSError, ValueError, KeyError, RuntimeError) as err:
        print(f"report: cannot read an input: {err}", file=sys.stderr)
        return 2

    # The source resolution: the first video stream of the capture, not of any derivative.
    src_stream = next(
        (s for s in source_probe.get("streams", []) if s.get("codec_type") == "video"),
        {},
    )
    capture = {
        "path": cut.get("source"),
        "seconds": round(
            float(source_probe.get("format", {}).get("duration") or 0.0), 3
        ),
        "width": int(src_stream.get("width") or 0),
        "height": int(src_stream.get("height") or 0),
    }

    content_seconds = float(cut.get("seconds") or 0.0)
    stuck_seconds = float(frozen.get("stuck_seconds") or 0.0)
    stuck_ratio = (
        round(stuck_seconds / content_seconds, 4) if content_seconds > 0 else 0.0
    )
    suspect = stuck_ratio > SUSPECT_RATIO

    upscaled = (
        master["height"] > capture["height"] or master["width"] > capture["width"]
    )
    master["upscaled"] = upscaled

    report = {
        "capture": capture,
        "content": {
            "begin": cut.get("begin"),
            "end": cut.get("end"),
            "seconds": round(content_seconds, 3),
            "broken": bool(cut.get("broken")),
        },
        "black": {
            "spans": cut.get("black_spans", []),
            "total_seconds": round(
                float(
                    sum(
                        float(s.get("seconds") or 0.0)
                        for s in cut.get("black_spans", [])
                    )
                ),
                3,
            ),
        },
        "frozen": {
            "spans": frozen.get("spans", []),
            "stuck_seconds": round(stuck_seconds, 3),
            "freeze_seconds": round(float(frozen.get("freeze_seconds") or 0.0), 3),
            "stuck_ratio": stuck_ratio,
        },
        "transcript": {
            "path": args.transcript,
            "bytes": os.path.getsize(args.transcript)
            if os.path.exists(args.transcript)
            else 0,
        },
        "master": master,
        "proxy": proxy,
        "suspect": suspect,
    }

    with open(args.out, "w") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")

    print(
        f"report: {report['content']['seconds']:.1f}s content, "
        f"{len(report['black']['spans'])} black span(s), "
        f"{len(report['frozen']['spans'])} frozen span(s) "
        f"({report['frozen']['stuck_seconds']:.1f}s stuck, "
        f"{report['frozen']['freeze_seconds']:.1f}s still), "
        f"master {master['width']}x{master['height']} "
        f"{master['bytes'] / 1024 / 1024:.1f} MiB, "
        f"proxy {proxy['bytes'] / 1024 / 1024:.1f} MiB"
        + (", SUSPECT" if suspect else ""),
        file=sys.stderr,
    )
    for span in report["frozen"]["spans"]:
        if span.get("class") != "stuck":
            continue
        print(
            f"report: stuck {span['start']:.2f}..{span['end']:.2f} "
            f"({span['seconds']:.1f}s) — check the tape",
            file=sys.stderr,
        )
    if suspect:
        print(
            f"report: SUSPECT — stuck for {stuck_ratio * 100:.0f}% of the content, more than a "
            f"third; the player paused or stalled",
            file=sys.stderr,
        )
    if upscaled:
        print(
            f"report: the master is {master['width']}x{master['height']} but the capture is "
            f"{capture['width']}x{capture['height']}: archiving never upscales",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
