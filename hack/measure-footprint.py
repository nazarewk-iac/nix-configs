#!/usr/bin/env python3
"""Measure a model's footprint, so the placement policy stops guessing.

The policy decides with numbers: VRAM, RAM, load seconds, decode and prefill rate. Those numbers
come from here — one run per model, on the host that will serve it.

What it does: unload the model, record the card, request it, sample the card while it loads, take
the rate from llama-swap's activity record, read the server's RSS, unload, and print the policy
fragment.

    hack/measure-footprint.py --model qwen3.5-4b --key-file /var/cache/llama-swap/api-keys

Run it on the serving host: it reads `/sys/class/drm` and `/proc`, and talks to the loopback API.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

DEFAULT_ENDPOINT = "http://127.0.0.1:39700"
PROMPT = "Reply with the single word: ready"


def api(endpoint: str, path: str, key: str, body: dict | None = None, timeout: int = 600):
    url = endpoint.rstrip("/") + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method="POST" if data else "GET")
    req.add_header("content-type", "application/json")
    if key:
        req.add_header("authorization", f"Bearer {key}")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw.strip().startswith((b"{", b"[")) else raw)
    except urllib.error.HTTPError as err:
        return err.code, err.read().decode(errors="replace")[:400]
    except urllib.error.URLError as err:
        return 0, str(err.reason)


def card_path() -> str:
    """The card with the most VRAM: on brys the R9700, not the RX 550 that enumerates first."""
    best, best_total = "", 0
    for entry in sorted(os.listdir("/sys/class/drm")):
        if not re.fullmatch(r"card\d+", entry):
            continue
        used = f"/sys/class/drm/{entry}/device/mem_info_vram_used"
        total = f"/sys/class/drm/{entry}/device/mem_info_vram_total"
        if not (os.path.exists(used) and os.path.exists(total)):
            continue
        with open(total) as fh:
            t = int(fh.read())
        if t > best_total:
            best, best_total = used, t
    return best


def vram_mib(path: str) -> int:
    try:
        with open(path) as fh:
            return int(fh.read()) // (1024 * 1024)
    except OSError:
        return 0


def rss_mib(model: str) -> int:
    """Resident memory of the server process that holds this model, in MiB."""
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as fh:
                cmdline = fh.read().replace(b"\x00", b" ").decode(errors="replace")
        except OSError:
            continue
        if "llama-server" not in cmdline or model not in cmdline:
            continue
        try:
            with open(f"/proc/{entry}/status") as fh:
                for line in fh:
                    if line.startswith("VmRSS:"):
                        return int(line.split()[1]) // 1024
        except OSError:
            continue
    return 0


def last_activity(endpoint: str, key: str, model: str) -> dict:
    status, body = api(endpoint, "/api/metrics/activity", key, timeout=30)
    if status != 200 or not isinstance(body, dict):
        return {}
    for record in reversed(body.get("data") or []):
        if record.get("model") == model:
            return record
    return {}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--endpoint", default=os.environ.get("LLAMASWAP", DEFAULT_ENDPOINT))
    ap.add_argument("--key-file", default="")
    ap.add_argument("--manager", default="http://127.0.0.1:8181")
    ap.add_argument("--card", default="", help="mem_info_vram_used path; defaults to the largest card")
    ap.add_argument("--settle", type=float, default=3.0, help="seconds to wait after readiness")
    ap.add_argument("--json", default="", help="write the fragment here as well")
    args = ap.parse_args()

    key = ""
    if args.key_file:
        with open(args.key_file) as fh:
            key = fh.readline().strip()
    card = args.card or card_path()
    if not card:
        raise SystemExit("no DRM card with VRAM found")

    # Pre-flight the placement policy: a refusal here is the answer, not a 500 from the entry.
    status, verdict = api(args.manager, "/decide", "", {"model": args.model}, timeout=30)
    if status == 200 and isinstance(verdict, dict) and verdict.get("verdict") != "admit":
        print(json.dumps(verdict, indent=2), file=sys.stderr)
        print(f"the policy refuses {args.model}; switch the profile or free the card first", file=sys.stderr)
        return 2

    # Unload first: a model that is already resident has no load time and no peak to measure.
    status, _ = api(args.endpoint, f"/api/models/unload/{args.model}", key, timeout=60)
    if status not in (200, 404, 405):
        print(f"unload returned {status}", file=sys.stderr)
    time.sleep(2)
    before = vram_mib(card)

    peak = {"mib": before}
    stop = threading.Event()

    def sample() -> None:
        while not stop.is_set():
            peak["mib"] = max(peak["mib"], vram_mib(card))
            time.sleep(0.5)

    sampler = threading.Thread(target=sample, daemon=True)
    sampler.start()

    start = time.monotonic()
    status, body = api(
        args.endpoint,
        "/v1/chat/completions",
        key,
        {
            "model": args.model,
            "messages": [{"role": "user", "content": PROMPT}],
            "max_tokens": 8,
        },
    )
    load_seconds = time.monotonic() - start
    stop.set()
    sampler.join(timeout=2)

    if status != 200:
        print(f"the request failed ({status}): {body}", file=sys.stderr)
        return 1

    time.sleep(args.settle)
    steady = vram_mib(card)
    ram = rss_mib(args.model)
    activity = last_activity(args.endpoint, key, args.model)

    fragment = {
        "vramMiB": steady,
        "ramMiB": ram,
        "loadSeconds": round(load_seconds),
        "decodeTps": round(float(activity.get("tokens_per_second") or 0), 1),
        "prefillTps": round(float(activity.get("prompt_per_second") or 0), 1),
        "measured": time.strftime("%Y-%m-%d"),
        "source": "hack/measure-footprint.py",
    }
    out = {
        "model": args.model,
        "card": card,
        "vramBeforeMiB": before,
        "vramPeakMiB": peak["mib"],
        "fragment": fragment,
    }
    print(json.dumps(out, indent=2))
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(out, fh, indent=2)

    api(args.endpoint, f"/api/models/unload/{args.model}", key, timeout=60)
    return 0


if __name__ == "__main__":
    sys.exit(main())
