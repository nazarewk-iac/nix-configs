#!/usr/bin/env python3
"""Drive a video edit with a vision model instead of a diffusion model.

The model reads sampled frames and answers with a plan — which spans to keep, where to cut, why.
It never touches a pixel: ffmpeg applies the plan, and `--mlt` writes a Kdenlive project so a human
can review the result. That split is the whole point: a 7B-class vision model is good at "which
shot is the keeper" and bad at "cut at 1.37 s", so the tool owns precision and the model owns
judgement.

The backend is any OpenAI-compatible chat endpoint that accepts image parts (`/chat/completions`),
so the same tool drives the local `qwen2.5-vl-7b` reviewer, the `qwen3-omni` companion, or a hosted
model. Everything deployment-specific is a flag or a file: the prompt, the JSON schema and the
frame plan are data.

Examples
--------
    # plan only: read the clip, print the edit, change nothing
    hack/video-edit.py --video clip.webm --model qwen2.5-vl-7b \
        --endpoint http://127.0.0.1:39700/v1 --key-file /var/cache/llama-swap/api-keys

    # plan and apply: cut the clip the way the model said, and write a Kdenlive project
    hack/video-edit.py --video clip.webm --model qwen2.5-vl-7b \
        --apply edited.webm --mlt edited.mlt

    # no model: show the sampled frames and the prompt that would be sent
    hack/video-edit.py --video clip.webm --model any --dry-run

Exit codes: 0 ok, 1 the model or ffmpeg failed, 2 bad usage or an unusable plan.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

DEFAULT_PROMPT = """\
You are editing a video. Below are {count} frames sampled from a {duration:.2f} second clip,
{width}x{height} at {fps:g} fps. Frame i was taken at t = {times} seconds.

Decide which spans to keep so the result is tight and coherent, and say what happens in each.

Answer with JSON only, no prose and no code fences:
{{"summary": str, "segments": [{{"start": seconds, "end": seconds, "keep": bool, "why": str}}]}}

Rules:
- Segments must cover the clip from 0 to {duration:.2f} in order, with no gaps and no overlaps.
- `keep: false` means cut it out. A two-second clip with one continuous action is one segment.
- Times must be numbers inside [0, {duration:.2f}]. Never invent frames you were not shown.
"""


# ---------------------------------------------------------------- process helpers


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    # ffmpeg writes its progress bar with ANSI escapes and the locale's encoding; `text=True` alone
    # raises UnicodeDecodeError on a frame of that, so decode defensively.
    return subprocess.run(cmd, capture_output=True, text=True, errors="replace", **kwargs)


def ffprobe_info(ffprobe: str, path: str) -> dict:
    out = run(
        [
            ffprobe, "-v", "error", "-print_format", "json",
            "-show_format", "-show_streams", path,
        ]
    )
    if out.returncode != 0:
        raise SystemExit(f"ffprobe failed on {path}: {out.stderr.strip()}")
    data = json.loads(out.stdout)
    video = next((s for s in data["streams"] if s.get("codec_type") == "video"), None)
    if video is None:
        raise SystemExit(f"{path} has no video stream")
    num, den = (video.get("r_frame_rate") or "25/1").split("/")
    fps = float(num) / float(den or 1)
    duration = float(data["format"].get("duration") or video.get("duration") or 0)
    return {
        "duration": duration,
        "width": int(video["width"]),
        "height": int(video["height"]),
        "fps": fps or 25.0,
    }


def scene_times(ffmpeg: str, path: str, threshold: float, duration: float) -> list[float]:
    """Timestamps where the picture changes enough to be a cut."""
    out = run(
        [
            ffmpeg, "-hide_banner", "-i", path,
            "-vf", f"select='gt(scene,{threshold})',showinfo",
            "-f", "null", "-",
        ]
    )
    times = [float(m) for m in re.findall(r"pts_time:([0-9.]+)", out.stderr)]
    return sorted(t for t in times if 0 < t < duration)


def frame_plan(
    times: list[float], duration: float, max_frames: int
) -> list[float]:
    """The timestamps to sample: every scene start, then a uniform grid to fill the budget."""
    plan: list[float] = [0.0]
    for t in times:
        if len(plan) >= max_frames - 1:
            break
        plan.append(round(t, 3))
    # A clip with no cuts still needs more than one frame to be judged.
    if len(plan) < min(3, max_frames):
        step = duration / min(max_frames, max(2, int(duration) or 2))
        t = 0.0
        while len(plan) < min(max_frames, 8) and t < duration:
            if all(abs(t - p) > step / 2 for p in plan):
                plan.append(round(t, 3))
            t += step
    plan = sorted(set(p for p in plan if p < duration))
    if plan and plan[-1] < duration - 0.15 and len(plan) < max_frames:
        plan.append(round(max(0.0, duration - 0.15), 3))
    return plan[:max_frames]


def extract(ffmpeg: str, path: str, times: list[float], outdir: str, max_edge: int, duration: float) -> list[str]:
    """One PNG per timestamp, longest edge capped so a frame costs ~400 tokens, not ~4000."""
    files = []
    for i, t in enumerate(times):
        # A seek into the last frame of a VP8/VP9 clip can land past the end and yield nothing.
        t = min(t, max(0.0, duration - 0.15))
        dest = os.path.join(outdir, f"frame-{i:03d}.png")
        scale = f"scale='if(gt(iw,ih),min({max_edge},iw),-2)':'if(gt(iw,ih),-2,min({max_edge},ih))'"
        out = run(
            [
                ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                "-ss", f"{t:.3f}", "-i", path, "-frames:v", "1",
                "-vf", scale, dest,
            ]
        )
        if out.returncode != 0 or not os.path.exists(dest):
            raise SystemExit(
                f"cannot extract a frame at {t:.3f}s (ffmpeg exit {out.returncode}): {out.stderr.strip()}"
            )
        files.append(dest)
    return files


# ---------------------------------------------------------------- the model


def call_model(endpoint: str, key: str, model: str, prompt: str, frames: list[str], timeout: int) -> str:
    content: list[dict] = [{"type": "text", "text": prompt}]
    for path in frames:
        with open(path, "rb") as fh:
            encoded = base64.b64encode(fh.read()).decode()
        content.append({"type": "image_url", "image_url": {"url": f"data:image/png;base64,{encoded}"}})
    body = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": content}],
            "max_tokens": 1200,
            "temperature": 0.2,
        }
    ).encode()
    req = urllib.request.Request(
        endpoint.rstrip("/") + "/chat/completions",
        data=body,
        headers={"content-type": "application/json", **({"authorization": f"Bearer {key}"} if key else {})},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")[:600]
        raise SystemExit(f"the endpoint answered {err.code}: {detail}")
    except urllib.error.URLError as err:
        raise SystemExit(f"cannot reach {endpoint}: {err.reason}")
    if "error" in payload:
        raise SystemExit(f"the model refused: {payload['error']}")
    message = payload["choices"][0]["message"]
    return (message.get("content") or "").strip()


def parse_plan(text: str) -> dict:
    """The model answers prose around JSON more often than not; take the outermost object."""
    fenced = re.search(r"```(?:json)?\s*(.*?)```", text, re.S)
    if fenced:
        text = fenced.group(1)
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        raise SystemExit(f"the answer carries no JSON object: {text[:300]!r}")
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError as err:
        raise SystemExit(f"the answer is not valid JSON ({err}): {text[start:end+1][:300]!r}")


def validate(plan: dict, duration: float) -> dict:
    """Clamp, sort and drop anything the tool cannot apply. A model's decimal is intent, not truth."""
    segments = plan.get("segments")
    if not isinstance(segments, list) or not segments:
        raise SystemExit("the plan has no segments")
    clean = []
    for raw in segments:
        try:
            start = float(raw.get("start"))
            end = float(raw.get("end"))
        except (TypeError, ValueError):
            continue
        start = max(0.0, min(start, duration))
        end = max(0.0, min(end, duration))
        if end - start < 0.05:
            continue
        clean.append(
            {
                "start": round(start, 3),
                "end": round(end, 3),
                "keep": bool(raw.get("keep", True)),
                "why": str(raw.get("why", "")).strip(),
            }
        )
    if not clean:
        raise SystemExit("every segment was unusable after clamping")
    clean.sort(key=lambda s: s["start"])
    return {"summary": str(plan.get("summary", "")).strip(), "segments": clean}


# ---------------------------------------------------------------- the tool owns precision


def snap(plan: dict, cuts: list[float], duration: float, window: float = 0.5) -> dict:
    """Move each boundary to the nearest detected scene cut, if one is within `window` seconds.

    The model sees one frame every few hundred milliseconds at best, so its timestamps are intent.
    A cut two frames off a scene change looks like a mistake; snapping makes it look deliberate.
    """
    if not cuts:
        return plan
    for seg in plan["segments"]:
        for key in ("start", "end"):
            t = seg[key]
            nearest = min(cuts, key=lambda c: abs(c - t), default=None)
            if nearest is not None and abs(nearest - t) <= window:
                seg[key] = round(nearest, 3)
    for seg in plan["segments"]:
        if seg["end"] <= seg["start"]:
            seg["end"] = min(duration, round(seg["start"] + 0.5, 3))
    return plan


def apply_plan(ffmpeg: str, source: str, plan: dict, dest: str, info: dict) -> None:
    """Cut the keep spans and concatenate them, re-encoding once."""
    keeps = [s for s in plan["segments"] if s["keep"]]
    if not keeps:
        raise SystemExit("the plan keeps nothing; refusing to write an empty video")
    filters, labels = [], []
    for i, seg in enumerate(keeps):
        filters.append(
            f"[0:v]trim=start={seg['start']:.3f}:end={seg['end']:.3f},setpts=PTS-STARTPTS[v{i}]"
        )
        labels.append(f"[v{i}]")
    filters.append("".join(labels) + f"concat=n={len(keeps)}:v=1:a=0[out]")
    out = run(
        [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", source,
            "-filter_complex", ";".join(filters), "-map", "[out]",
            "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "30", dest,
        ]
    )
    if out.returncode != 0:
        raise SystemExit(f"ffmpeg could not apply the plan: {out.stderr.strip()}")
    kept = sum(s["end"] - s["start"] for s in keeps)
    print(f"applied: {len(keeps)} span(s), {kept:.2f}s of {info['duration']:.2f}s -> {dest}", file=sys.stderr)


def write_mlt(source: str, plan: dict, dest: str, info: dict) -> None:
    """A Kdenlive-openable project: one playlist entry per kept span, on one track."""
    fps = info["fps"]
    entries = []
    for seg in plan["segments"]:
        if not seg["keep"]:
            continue
        entries.append(
            f'    <entry producer="producer0" in="{int(seg["start"] * fps)}" out="{max(int(seg["start"] * fps), int(seg["end"] * fps) - 1)}"/>'
        )
    last = max((int(s["end"] * fps) for s in plan["segments"] if s["keep"]), default=1) - 1
    xml = "\n".join(
        [
            '<?xml version="1.0" encoding="utf-8"?>',
            f'<mlt LC_NUMERIC="C" version="7.0.0" title="{os.path.basename(dest)}" producer="tractor0">',
            f'  <profile description="{info["width"]}x{info["height"]}" width="{info["width"]}" height="{info["height"]}" '
            f'progressive="1" sample_aspect_num="1" sample_aspect_den="1" display_aspect_num="{info["width"]}" '
            f'display_aspect_den="{info["height"]}" frame_rate_num="{int(round(fps))}" frame_rate_den="1" colorspace="709"/>',
            f'  <producer id="producer0" in="0" out="{last}">',
            f'    <property name="resource">{os.path.abspath(source)}</property>',
            "  </producer>",
            '  <playlist id="playlist0">',
            *entries,
            "  </playlist>",
            f'  <tractor id="tractor0" in="0" out="{last}">',
            '    <track producer="playlist0"/>',
            "  </tractor>",
            "</mlt>",
            "",
        ]
    )
    with open(dest, "w") as fh:
        fh.write(xml)
    print(f"kdenlive project: {dest}", file=sys.stderr)


# ---------------------------------------------------------------- cli


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Plan a video edit with a vision model and apply it with ffmpeg.")
    ap.add_argument("--video", required=True, help="source clip")
    ap.add_argument("--model", required=True, help="model id at the endpoint")
    ap.add_argument("--endpoint", default=os.environ.get("VIDEO_EDIT_ENDPOINT", "http://127.0.0.1:39700/v1"))
    ap.add_argument("--key-env", default="VIDEO_EDIT_KEY", help="environment variable holding the bearer key")
    ap.add_argument("--key-file", default="", help="file whose first line is the bearer key")
    ap.add_argument("--scene-threshold", type=float, default=0.3, help="ffmpeg scene score that counts as a cut")
    ap.add_argument("--max-frames", type=int, default=24, help="frames to send; ~400 tokens each")
    ap.add_argument("--max-edge", type=int, default=768, help="longest edge of a sampled frame, px")
    ap.add_argument("--prompt-file", default="", help="replace the built-in prompt ({count} etc. still apply)")
    ap.add_argument("--plan-in", default="", help="apply this plan instead of asking the model (hand-editable)")
    ap.add_argument("--plan-out", default="", help="write the validated plan here (JSON)")
    ap.add_argument("--apply", default="", help="write the edited video here")
    ap.add_argument("--mlt", default="", help="write a Kdenlive project here")
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--dry-run", action="store_true", help="sample frames and print the prompt; do not call the model")
    ap.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    ap.add_argument("--ffprobe", default=shutil.which("ffprobe") or "ffprobe")
    args = ap.parse_args(argv)

    info = ffprobe_info(args.ffprobe, args.video)
    cuts = scene_times(args.ffmpeg, args.video, args.scene_threshold, info["duration"])

    if args.plan_in:
        # A plan is data: it can be written by a person, reviewed in a diff, and applied without a
        # model in the loop. That is also the offline test of the apply path.
        with open(args.plan_in) as fh:
            plan = snap(validate(json.load(fh), info["duration"]), cuts, info["duration"])
        print(json.dumps(plan, indent=2))
        if args.plan_out:
            with open(args.plan_out, "w") as fh:
                json.dump(plan, fh, indent=2)
        if args.apply:
            apply_plan(args.ffmpeg, args.video, plan, args.apply, info)
        if args.mlt:
            write_mlt(args.video, plan, args.mlt, info)
        return 0

    times = frame_plan(cuts, info["duration"], args.max_frames)
    if not times:
        raise SystemExit("no frames to sample")

    with tempfile.TemporaryDirectory(prefix="video-edit-") as tmp:
        frames = extract(args.ffmpeg, args.video, times, tmp, args.max_edge, info["duration"])
        template = DEFAULT_PROMPT
        if args.prompt_file:
            with open(args.prompt_file) as fh:
                template = fh.read()
        prompt = template.format(
            count=len(times),
            duration=info["duration"],
            width=info["width"],
            height=info["height"],
            fps=info["fps"],
            times=", ".join(f"{t:.2f}" for t in times),
        )
        if args.dry_run:
            print(prompt)
            print(f"\n{len(frames)} frames at {times}", file=sys.stderr)
            return 0

        key = ""
        if args.key_file:
            with open(args.key_file) as fh:
                key = fh.readline().strip()
        elif args.key_env:
            key = os.environ.get(args.key_env, "")

        answer = call_model(args.endpoint, key, args.model, prompt, frames, args.timeout)

    plan = snap(validate(parse_plan(answer), info["duration"]), cuts, info["duration"])
    print(json.dumps(plan, indent=2))
    if args.plan_out:
        with open(args.plan_out, "w") as fh:
            json.dump(plan, fh, indent=2)
    if args.apply:
        apply_plan(args.ffmpeg, args.video, plan, args.apply, info)
    if args.mlt:
        write_mlt(args.video, plan, args.mlt, info)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
