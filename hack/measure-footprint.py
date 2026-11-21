#!/usr/bin/env python3
"""Measure a model's footprint, so the placement policy stops guessing.

The policy decides with numbers: VRAM, RAM, load seconds, decode and prefill rate. Those numbers
come from here — one run per model, on the host that will serve it.

What it does: check the placement policy, wait for the card to be still, request the model, sample
the card while it loads, take the rate from llama-swap's activity record, read the server's RSS, and
print the policy fragment.

    hack/measure-footprint.py --model qwen3.5-4b --key-file /var/cache/llama-swap/api-keys

Run it on the serving host: it reads `/sys/class/drm` and `/proc`, and talks to the loopback API.
The model must not be resident when it starts; the tool refuses rather than measure a cached load.

Three waits matter, and every one of them was missing:

* **The card must be still before the baseline is read.** A model that is still paging in makes
  `before` a moving target, so the delta is a lottery. `settle_card` polls for a still card.
* **The activity record is written after the response.** The rate is appended to the ring once the
  request has finished, which is a moment after the client sees the body. Reading once returns the
  *previous* record for the same model — or nothing — and `decodeTps`/`prefillTps` come back as 0.0.
  `await_activity` polls for a record with an id above the pre-request high-water mark.
* **The activity ring is newest-first.** The old read walked it backwards, so it started at the
  oldest record for the model, which is usually a failed request reporting 0 t/s. `await_activity`
  sorts by id and never trusts the order the endpoint returns.

The rates are also nested under `tokens` in the record, and the old flat read of
`tokens_per_second` could only ever return the default 0.0.

The card figure the policy needs is the model's **own** footprint, because `fits-beside` compares it
against free VRAM. Anything resident beside the model is in both samples and cancels out, so the
fragment reports `steady - before` and prints the absolutes beside it for the record.
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


def api(
    endpoint: str,
    path: str,
    key: str,
    body: dict | None = None,
    timeout: int = 600,
    method: str = "",
):
    url = endpoint.rstrip("/") + path
    data = json.dumps(body).encode() if body is not None else None
    # A POST with no body is a real request (`/api/models/unload/<model>` takes none). Deriving the
    # method from the body turned those into GETs, which llama-swap answers 200 and ignores.
    verb = method or ("POST" if data else "GET")
    req = urllib.request.Request(url, data=data, method=verb)
    req.add_header("content-type", "application/json")
    if key:
        req.add_header("authorization", f"Bearer {key}")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            return resp.status, (
                json.loads(raw) if raw.strip().startswith((b"{", b"[")) else raw
            )
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


def activity(endpoint: str, key: str) -> list:
    """The activity ring, newest last. Empty when the endpoint cannot be read."""
    status, body = api(endpoint, "/api/metrics/activity", key, timeout=30)
    if status != 200 or not isinstance(body, dict):
        return []
    return [r for r in (body.get("data") or []) if isinstance(r, dict)]


def activity_high_water(endpoint: str, key: str) -> int:
    """The newest record id before the request, so the record the request adds can be told apart.

    The ring is small and it is shared: without this mark the newest record for the model may be
    the previous measurement, or a failed request that reports 0 t/s.
    """
    return max(
        (r["id"] for r in activity(endpoint, key) if isinstance(r.get("id"), int)),
        default=0,
    )


def await_activity(
    endpoint: str, key: str, model: str, after_id: int, timeout: float
) -> dict:
    """The activity record for this request, polled for until it appears.

    Two traps, both of which return a *stale* record and a rate of 0.0:

    * The ring is written after the response, so a single read right after the body usually misses
      the record this request added. Poll instead of sleeping a fixed time, because a cold prefill
      takes longer than any sleep short enough to be cheap.
    * The ring is ordered newest-first. Walking it backwards starts at the oldest record for the
      model, which is typically a failed request that reports 0 t/s. Sort by id instead of trusting
      the order the endpoint happens to return.
    """
    deadline = time.monotonic() + timeout
    while True:
        records = [r for r in activity(endpoint, key) if r.get("model") == model]
        records.sort(
            key=lambda r: r.get("id") if isinstance(r.get("id"), int) else 0,
            reverse=True,
        )
        for record in records:
            rid = record.get("id")
            # Only a record above the pre-request mark was written by this request.
            if not isinstance(rid, int) or rid > after_id:
                return record
        if time.monotonic() >= deadline:
            return {}
        time.sleep(0.5)


def running_models(endpoint: str, key: str) -> set:
    """The models llama-swap reports as running right now.

    `/running` answers a list of objects, one per running entry, so a plain set of the list items
    would never match a model name.
    """
    status, body = api(endpoint, "/running", key, timeout=30)
    if status != 200 or not isinstance(body, dict):
        return set()
    names = set()
    for entry in body.get("running") or []:
        if isinstance(entry, str):
            names.add(entry)
        elif isinstance(entry, dict):
            name = entry.get("model") or entry.get("name")
            if name:
                names.add(str(name))
    return names


def settle_card(card: str, timeout: float, floor: int = -1) -> int:
    """Wait until the card stops moving, and return the settled VRAM in MiB.

    The baseline is only a baseline if nothing is loading while it is read. A model that is still
    being paged in makes `before` a moving target and the delta a lottery.
    """
    deadline = time.monotonic() + timeout
    last, stable = -1, 0
    while time.monotonic() < deadline:
        now = vram_mib(card)
        stable = stable + 1 if now == last else 0
        last = now
        if stable >= 6 and now > floor:
            return now
        time.sleep(0.5)
    print(
        f"the card did not settle within {timeout:.0f}s; using the last reading",
        file=sys.stderr,
    )
    return vram_mib(card)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--endpoint", default=os.environ.get("LLAMASWAP", DEFAULT_ENDPOINT))
    ap.add_argument("--key-file", default="")
    ap.add_argument("--manager", default="http://127.0.0.1:8181")
    ap.add_argument(
        "--card",
        default="",
        help="mem_info_vram_used path; defaults to the largest card",
    )
    ap.add_argument(
        "--settle", type=float, default=3.0, help="seconds to wait after readiness"
    )
    ap.add_argument(
        "--settle-timeout",
        type=float,
        default=180.0,
        help="seconds to wait for the card to stop moving before the baseline is read",
    )
    ap.add_argument(
        "--activity-timeout",
        type=float,
        default=60.0,
        help="seconds to wait for the activity record of this request",
    )
    ap.add_argument("--json", default="", help="write the fragment here as well")
    ap.add_argument(
        "--cooldown-retries",
        type=int,
        default=2,
        help="how often to wait out the policy's switch cooldown before giving up",
    )
    ap.add_argument(
        "--cooldown-wait",
        type=float,
        default=35.0,
        help="seconds to wait for the switch cooldown to clear",
    )
    args = ap.parse_args()

    key = ""
    if args.key_file:
        with open(args.key_file) as fh:
            key = fh.readline().strip()
    card = args.card or card_path()
    if not card:
        raise SystemExit("no DRM card with VRAM found")

    # Pre-flight the placement policy: a refusal here is the answer, not a 500 from the entry.
    # The one refusal worth waiting out is the switch cooldown: the operator has just moved the box
    # to the profile this model needs, and a measurement should not fail because of the debounce it
    # asked for.
    for attempt in range(args.cooldown_retries + 1):
        status, verdict = api(
            args.manager, "/decide", "", {"model": args.model}, timeout=30
        )
        if (
            status == 200
            and isinstance(verdict, dict)
            and verdict.get("verdict") != "admit"
        ):
            refusal = verdict.get("refusal") or {}
            if refusal.get("code") == 429 and attempt < args.cooldown_retries:
                print(
                    f"the policy is in its switch cooldown; waiting {args.cooldown_wait:.0f}s",
                    file=sys.stderr,
                )
                time.sleep(args.cooldown_wait)
                continue
            print(json.dumps(verdict, indent=2), file=sys.stderr)
            print(
                f"the policy refuses {args.model}; switch the profile or free the card first",
                file=sys.stderr,
            )
            return 2
        break

    # The model must not be resident: an already-loaded model has no load time, and the request
    # would reuse the previous footprint. Refuse rather than measure nothing.
    #
    # The tool deliberately does not unload it. A companion belongs to llama-swap's `with_co`
    # group, so unloading it takes the frontier with it, the engine is then gone while the manager
    # still reports its profile, and the restore lands on the first text profile (`max`, the whole
    # card) where the companion no longer fits. One unload therefore costs a profile switch back,
    # which is the operator's call, not a side effect of a measurement.
    if args.model in running_models(args.endpoint, key):
        print(
            f"{args.model} is already resident; its load time and its own footprint cannot be "
            "measured.\nPut it away and bring the resting profile back, then run again:\n"
            "  sudo -n kdn-inference-helpers ctl unload\n"
            "  sudo -n kdn-inference-helpers ctl up --profile omni-fast",
            file=sys.stderr,
        )
        return 3
    before = settle_card(card, args.settle_timeout)
    mark = activity_high_water(args.endpoint, key)

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
    # Poll, do not sleep: the record lands after the body, and a fixed wait is either too short or
    # too long. The timeout is generous because a cold prefill of a large model is slow.
    record = await_activity(args.endpoint, key, args.model, mark, args.activity_timeout)
    # The rates are nested under `tokens`. A flat read of `tokens_per_second` is always absent, and
    # that — not only the timing — is why every measurement reported 0.0 t/s.
    tokens = record.get("tokens") or {}

    # The model's own footprint: whatever else is resident is in both samples and cancels out. The
    # policy compares this number against free VRAM (`fits-beside`), so an absolute card reading
    # would double-count the frontier.
    own = max(steady - before, 0)

    fragment = {
        "vramMiB": own,
        "ramMiB": ram,
        "loadSeconds": round(load_seconds),
        "decodeTps": round(float(tokens.get("tokens_per_second") or 0), 1),
        "prefillTps": round(float(tokens.get("prompt_per_second") or 0), 1),
        "measured": time.strftime("%Y-%m-%d"),
        "source": "hack/measure-footprint.py",
    }
    out = {
        "model": args.model,
        "card": card,
        "vramBeforeMiB": before,
        "vramSteadyMiB": steady,
        "vramPeakMiB": peak["mib"],
        "activityId": record.get("id"),
        "activityStatus": record.get("resp_status_code"),
        "fragment": fragment,
    }
    print(json.dumps(out, indent=2))
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(out, fh, indent=2)

    # The model is left resident on purpose: unloading it costs a profile switch (see above), so the
    # operator decides when to pay that.
    print(
        f"{args.model} is left resident; `ctl unload` frees it, and the profile then needs "
        "`ctl up --profile <colo>`",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
