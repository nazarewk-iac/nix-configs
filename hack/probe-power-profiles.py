#!/usr/bin/env python3
"""The table: three profiles x two cap states, decode and long prefill.

Profiles are the engine's operating points, not model names:

  max       UD-IQ4_XS on the whole card            (73 t/s at 1M)
  omni-fast IQ2_XS + 21.5 GB reserve               (72 t/s at 1M, the companion fits)
  omni-max  UD-IQ4_XS + 21.5 GB reserve            (42 t/s at 1M, the best pack with a reserve)

Cap states: 300 W (the factory value, written explicitly so the card is in a known state) and the
card's floor, 210 W.

Decode skips the first 64 tokens and reports the median of five runs. Long prefill is a ~32k-token
prompt that starts with a random nonce, so the prefix cache can never answer it; the rate is
prompt_tokens over time-to-first-token.
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
CAPS = [300, 210]
DECODE_RUNS, DECODE_TOKENS, SKIP = 5, 768, 64
PREFILL_WORDS = 24000          # ~32k tokens
PREFILL_RUNS = 2
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
    body = json.dumps({"profile": profile}).encode()
    req = urllib.request.Request(f"{MANAGER}/select", body, {"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        out = json.load(r)
    print(f"    select {profile}: {round(time.time() - t0, 1)}s {out}", flush=True)


def decode_once(tokens=DECODE_TOKENS):
    s = Sampler(); s.start()
    stamps = []
    with post({"model": "qfn", "temperature": 0, "stream": True, "max_tokens": tokens,
               "messages": [{"role": "user", "content": "List the integers from 1 upward, one per line."}]}) as r:
        for line in r:
            if line.startswith(b"data: ") and line.strip() != b"data: [DONE]":
                stamps.append(time.time())
    s.stop.set(); s.join()
    if len(stamps) <= SKIP + 8:
        return None, None, None
    span = stamps[-1] - stamps[SKIP]
    return ((len(stamps) - 1 - SKIP) / span, statistics.mean(s.power),
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
    return pt, pt / ttft if ttft else None, statistics.mean(s.power) if s.power else None


rows = []
for profile in PROFILES:
    print(f"\n== profile {profile} ==", flush=True)
    select(profile)
    for cap in CAPS:
        set_cap(cap)
        time.sleep(15)
        dec, powers, temps = [], [], []
        for _ in range(DECODE_RUNS):
            tps, p, t = decode_once()
            if tps:
                dec.append(tps)
            if p:
                powers.append(p)
            if t:
                temps.append(t)
            time.sleep(2)
        pres = []
        for _ in range(PREFILL_RUNS):
            pt, tps, p = prefill_once()
            if tps:
                pres.append(tps)
            time.sleep(2)
        row = {"profile": profile, "cap": cap,
               "decode": round(statistics.median(dec), 1) if dec else None,
               "decode_min": round(min(dec), 1) if dec else None,
               "decode_max": round(max(dec), 1) if dec else None,
               "prefill": round(statistics.median(pres), 1) if pres else None,
               "prompt": pt,
               "power": round(statistics.median(powers), 1) if powers else None,
               "temp": round(statistics.median(temps), 1) if temps else None}
        rows.append(row)
        print(f"  {cap:>3} W  decode {row['decode']} t/s [{row['decode_min']}-{row['decode_max']}]  "
              f"prefill {row['prefill']} t/s ({pt} tok)  {row['power']} W  {row['temp']} C", flush=True)

print("\n| profile | cap W | decode t/s | decode range | long prefill t/s | prompt tok | power W | junction C |")
print("| ------- | ----: | ---------: | -----------: | ---------------: | ---------: | ------: | ---------: |")
for r in rows:
    print(f"| {r['profile']} | {r['cap']:>5} | {r['decode']:10.1f} | "
          f"{r['decode_min']:5.1f}-{r['decode_max']:5.1f} | {r['prefill']:16.1f} | "
          f"{r['prompt']:10} | {r['power']:7} | {r['temp']:10} |")
print("\nrows:", json.dumps(rows))
