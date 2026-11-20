#!/usr/bin/env python3
"""Clean power-cap measurement: decode with many samples, prefill with a unique prefix.

Two mistakes from the first sweep are fixed here:

- The prefill prompt was identical every time, so the engine's prefix cache turned a 1.2k t/s cold
  prefill into a 46k t/s cache hit. Each run now starts with a different nonce, so the prefix can
  never match.
- Decode was timed over the whole generation, where speculative-acceptance varies with the content
  of the first tokens. Each run now skips the first 64 tokens and reports the median over samples,
  not the best one.
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
SWAP = "http://127.0.0.1:39700/v1/chat/completions"
KEY = subprocess.run(
    ["sudo", "-n", "cat", "/var/cache/llama-swap/api-keys"],
    capture_output=True, text=True, check=True,
).stdout.split("\n")[0].strip()
CAPS = [300, 260, 230, 210]
DECODE_RUNS, DECODE_TOKENS, SKIP = 5, 768, 64
PREFILL_RUNS, PREFILL_WORDS = 3, 1000


def rd(p):
    try:
        return int(open(p).read().strip())
    except Exception:
        return None


def set_cap(watts):
    p = subprocess.run(["sudo", "-n", "tee", CAP], input=f"{watts * 1000000}\n",
                       capture_output=True, text=True)
    time.sleep(1.5)
    back = (rd(CAP) or 0) / 1e6
    if abs(back - watts) > 1:
        raise SystemExit(f"cap {watts} refused: {p.stderr.strip()}")
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
    return urllib.request.urlopen(req, timeout=1800)


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
        return None, s
    span = stamps[-1] - stamps[SKIP]
    n = len(stamps) - 1 - SKIP
    return (n / span if span else None), s


def prefill_once():
    nonce = "%08x" % random.getrandbits(32)
    words = " ".join(random.choice(("alpha", "bravo", "charlie", "delta", "echo"))
                     for _ in range(PREFILL_WORDS))
    s = Sampler(); s.start()
    t0 = time.time()
    with post({"model": "qfn", "temperature": 0, "stream": False, "max_tokens": 1,
               "messages": [{"role": "user",
                             "content": f"Reference {nonce}: {words}\n\nReply with the word: ok"}]}) as r:
        body = json.load(r)
    ttft = time.time() - t0
    s.stop.set(); s.join()
    pt = (body.get("usage") or {}).get("prompt_tokens") or 0
    return pt / ttft if ttft else None, pt, s


def new_kernel_errors(marker):
    out = subprocess.run(["sudo", "-n", "dmesg"], capture_output=True, text=True).stdout
    lines = out.splitlines()
    fresh = lines[marker:] if marker < len(lines) else []
    return [ln for ln in fresh
            if ("GPU reset" in ln or "ring gfx" in ln and "timeout" in ln
                or "amdgpu" in ln and ("ERROR" in ln or "failed" in ln.lower()))], len(lines)


err_marker = new_kernel_errors(0)[1]
print(f"dmesg marker at line {err_marker}", flush=True)

rows = []
for cap in CAPS:
    set_cap(cap)
    time.sleep(15)
    decs, powers, temps = [], [], []
    for _ in range(DECODE_RUNS):
        tps, s = decode_once()
        if tps:
            decs.append(tps)
        if s.power:
            powers.append(statistics.mean(s.power))
        if s.temps:
            temps.append(max(s.temps))
        time.sleep(1)
    pres = []
    for _ in range(PREFILL_RUNS):
        tps, pt, s = prefill_once()
        if tps:
            pres.append(tps)
        time.sleep(1)
    errs, _ = new_kernel_errors(err_marker)
    row = {"cap": cap,
           "decode_med": round(statistics.median(decs), 1),
           "decode_min": round(min(decs), 1), "decode_max": round(max(decs), 1),
           "prefill_med": round(statistics.median(pres), 1),
           "prompt": pt,
           "power": round(statistics.median(powers), 1),
           "temp": round(statistics.median(temps), 1),
           "new_errors": len(errs)}
    rows.append(row)
    print(f"  {cap:>3} W  decode {row['decode_med']:5.1f} t/s "
          f"[{row['decode_min']}-{row['decode_max']}]  prefill {row['prefill_med']:7.1f} t/s "
          f"({pt} tok)  {row['power']} W  {row['temp']} C  errors+{row['new_errors']}", flush=True)

base = rows[0]
print("\n| cap W | decode t/s (median) | vs 300 W | decode range | prefill t/s | power mean W | junction C |")
print("| ----: | ------------------: | -------: | -----------: | ----------: | -----------: | ---------: |")
for r in rows:
    print(f"| {r['cap']:>5} | {r['decode_med']:19.1f} | "
          f"{(r['decode_med'] - base['decode_med']) / base['decode_med'] * 100:+6.1f} % | "
          f"{r['decode_min']:5.1f}-{r['decode_max']:5.1f} | {r['prefill_med']:11.1f} | "
          f"{r['power']:12} | {r['temp']:9} |")
print("\nrows:", json.dumps(rows))
