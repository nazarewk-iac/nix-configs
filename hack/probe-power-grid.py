#!/usr/bin/env python3
"""The grid behind the curves: every profile x every reachable cap, decode and long prefill.

Profiles are the engine's operating points (a switch per profile, then the caps inside it):

  max       UD-IQ4_XS on the whole card
  omni-fast IQ2_XS + 21.5 GB reserve (the companion fits)
  omni-max  UD-IQ4_XS + 21.5 GB reserve

Caps: 300 W (the factory value) down to 210 W (the card's `power1_cap_min`; below it the SMU
refuses the write). Caps descend inside a profile, which is the order a person would use.

Decode skips the first 64 streamed tokens (speculative acceptance settles) and reports the median of
three runs plus the range. Long prefill is a ~32k-token prompt that begins with a random nonce, so
the prefix cache can never answer it; the rate is prompt_tokens over time-to-first-token.
"""
import json
import random
import statistics
import subprocess
import threading
import time
import urllib.request

HW = "/sys/class/drm/card1/device/hwmon/hwmon2"
CAP = f"{HW}/power1_cap"
MANAGER = "http://127.0.0.1:8181"
SWAP = "http://127.0.0.1:39700/v1/chat/completions"
KEY = subprocess.run(
    ["sudo", "-n", "cat", "/var/cache/llama-swap/api-keys"],
    capture_output=True, text=True, check=True,
).stdout.split("\n")[0].strip()

PROFILES = ["max", "omni-fast", "omni-max"]
CAPS = [300, 275, 250, 225, 210]
DECODE_RUNS, DECODE_TOKENS, SKIP = 3, 768, 64
PREFILL_WORDS, PREFILL_RUNS = 24000, 2
WORDS = ("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike "
         "november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu").split()


def rd(p):
    try:
        return int(open(p).read().strip())
    except Exception:
        return None


def set_cap(watts):
    subprocess.run(["sudo", "-n", "tee", CAP], input=f"{watts * 1000000}\n",
                   capture_output=True, text=True)
    time.sleep(1.5)
    back = (rd(CAP) or 0) / 1e6
    if abs(back - watts) > 1:
        raise SystemExit(f"cap {watts} W refused, card reports {back} W")
    return back


class Sampler(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.power, self.temps, self.stop = [], [], threading.Event()

    def run(self):
        while not self.stop.is_set():
            v = rd(f"{HW}/power1_average")
            if v:
                self.power.append(v / 1e6)
            t = rd(f"{HW}/temp1_input")
            if t:
                self.temps.append(t / 1000)
            time.sleep(0.2)


def post(body):
    req = urllib.request.Request(SWAP, json.dumps(body).encode(),
                                 {"Content-Type": "application/json",
                                  "Authorization": f"Bearer {KEY}"})
    return urllib.request.urlopen(req, timeout=3600)


def select(profile):
    req = urllib.request.Request(f"{MANAGER}/select",
                                 json.dumps({"profile": profile}).encode(),
                                 {"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        out = json.load(r)
    print(f"    select {profile}: {round(time.time() - t0, 1)}s {out}", flush=True)


def warm(tries=30, pause=2.0):
    """A tiny request until the entry answers; a switch can leave the first request racing."""
    for i in range(tries):
        try:
            with post({"model": "qfn", "temperature": 0, "stream": False, "max_tokens": 4,
                       "messages": [{"role": "user", "content": "hi"}]}) as r:
                r.read()
            return True
        except Exception as e:  # noqa: BLE001
            print(f"    warm-up {i + 1}: {type(e).__name__} {str(e)[:40]}", flush=True)
            time.sleep(pause)
    return False


def retry(fn, tries=3):
    for i in range(tries):
        try:
            return fn()
        except Exception as e:  # noqa: BLE001
            print(f"    retry {i + 1}: {type(e).__name__} {str(e)[:50]}", flush=True)
            time.sleep(5)
    return None, None, None


def decode_once():
    s = Sampler(); s.start()
    stamps = []
    with post({"model": "qfn", "temperature": 0, "stream": True, "max_tokens": DECODE_TOKENS,
               "messages": [{"role": "user",
                             "content": "List the integers from 1 upward, one per line."}]}) as r:
        for line in r:
            if line.startswith(b"data: ") and line.strip() != b"data: [DONE]":
                stamps.append(time.time())
    s.stop.set(); s.join()
    if len(stamps) <= SKIP + 8:
        return None, None, None
    span = stamps[-1] - stamps[SKIP]
    return ((len(stamps) - 1 - SKIP) / span,
            statistics.mean(s.power) if s.power else None,
            max(s.temps) if s.temps else None)


def prefill_once():
    nonce = "%08x" % random.getrandbits(32)
    words = " ".join(random.choice(WORDS) for _ in range(PREFILL_WORDS))
    s = Sampler(); s.start()
    t0 = time.time()
    with post({"model": "qfn", "temperature": 0, "stream": False, "max_tokens": 1,
               "messages": [{"role": "user",
                             "content": f"Case {nonce}. {words}\n\nReply with: ok"}]}) as r:
        body = json.load(r)
    ttft = time.time() - t0
    s.stop.set(); s.join()
    pt = (body.get("usage") or {}).get("prompt_tokens") or 0
    return pt, (pt / ttft if ttft else None), (statistics.mean(s.power) if s.power else None)


rows = []
for profile in PROFILES:
    print(f"\n== profile {profile} ==", flush=True)
    select(profile)
    if not warm():
        raise SystemExit(f"the {profile} entry never answered after the switch")
    for cap in CAPS:
        set_cap(cap)
        time.sleep(12)
        dec, pw, tp = [], [], []
        for _ in range(DECODE_RUNS):
            tps, p, t = retry(decode_once)
            if tps:
                dec.append(tps)
            if p:
                pw.append(p)
            if t:
                tp.append(t)
            time.sleep(2)
        pres = []
        for _ in range(PREFILL_RUNS):
            pt, tps, _ = retry(prefill_once)
            if tps:
                pres.append(tps)
            time.sleep(2)
        row = {"profile": profile, "cap": cap,
               "decode": round(statistics.median(dec), 1) if dec else None,
               "decode_min": round(min(dec), 1) if dec else None,
               "decode_max": round(max(dec), 1) if dec else None,
               "prefill": round(statistics.median(pres), 1) if pres else None,
               "prompt": pt,
               "power": round(statistics.median(pw), 1) if pw else None,
               "temp": round(statistics.median(tp), 1) if tp else None}
        rows.append(row)
        print(f"  {cap:>3} W  decode {row['decode']:5.1f} [{row['decode_min']}-{row['decode_max']}]  "
              f"prefill {row['prefill']:7.1f} ({pt} tok)  {row['power']} W  {row['temp']} C", flush=True)

print("\nGRID-JSON " + json.dumps(rows), flush=True)
