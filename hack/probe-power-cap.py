#!/usr/bin/env python3
"""Power-cap sweep for the served engine, plus what happens below the card's floor.

Order: 300 W (baseline, no write) -> 250 -> 225 -> 210 (the advertised floor) -> attempts at 200,
175, 150, 100 and 50 W, where each attempt reports exactly what the driver does with the write ->
back to the chosen cap -> a sustained-stability loop.

Decode is measured between the first and last streamed token so prefill stays out of it; prefill is
a ~6k-token prompt timed to the first byte.
"""
import json
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
FILLER = "The quick brown fox jumps over the lazy dog. " * 700
MEASURE_CAPS = [300, 250, 225, 210]
ATTEMPT_CAPS = [200, 175, 150, 100, 50]


def read(path):
    try:
        return int(open(path).read().strip())
    except Exception:
        return None


def cap_now():
    return (read(CAP) or 0) / 1e6


def write_cap(watts):
    """Write and report (read-back, stderr). The driver rejects out-of-range values with EINVAL."""
    p = subprocess.run(["sudo", "-n", "tee", CAP], input=f"{watts * 1000000}\n",
                       capture_output=True, text=True)
    time.sleep(1.5)
    err = (p.stderr or "").strip().splitlines()
    return cap_now(), (err[0] if err else "")


class Sampler(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.power, self.temps, self.stop = [], [], threading.Event()

    def run(self):
        while not self.stop.is_set():
            p = read(f"{HW}/power1_average")
            if p:
                self.power.append(p / 1e6)
            t = read(f"{HW}/temp1_input")
            if t:
                self.temps.append(t / 1000)
            time.sleep(0.25)


def chat(messages, max_tokens, stream):
    body = json.dumps({"model": "qfn", "messages": messages, "max_tokens": max_tokens,
                       "temperature": 0, "stream": stream}).encode()
    req = urllib.request.Request(SWAP, body, {
        "Content-Type": "application/json", "Authorization": f"Bearer {KEY}"})
    return urllib.request.urlopen(req, timeout=1800)


def decode_rate(tokens=512):
    s = Sampler(); s.start()
    first = last = None; n = 0
    t0 = time.time()
    with chat([{"role": "user", "content": "Count from 1 to 800, one number per line."}],
              tokens, True) as r:
        for line in r:
            if not line.startswith(b"data: ") or line.strip() == b"data: [DONE]":
                continue
            now = time.time(); first = first or now; last = now; n += 1
    s.stop.set(); s.join()
    gen = (last - first) if first and last else 1e-9
    return {"tps": (n - 1) / gen if n > 1 else 0.0, "n": n,
            "wall": round(time.time() - t0, 1),
            "pmean": round(statistics.mean(s.power), 1) if s.power else None,
            "pmax": round(max(s.power), 1) if s.power else None,
            "tmax": round(max(s.temps), 1) if s.temps else None}


def prefill_rate():
    s = Sampler(); s.start()
    t0 = time.time()
    with chat([{"role": "user", "content": FILLER + "\nReply with: ok"}], 1, False) as r:
        body = json.load(r)
    ttft = time.time() - t0
    s.stop.set(); s.join()
    pt = (body.get("usage") or {}).get("prompt_tokens") or 0
    return {"tps": round(pt / ttft, 1) if ttft else 0.0, "pt": pt,
            "pmean": round(statistics.mean(s.power), 1) if s.power else None}


def gpu_errors():
    out = subprocess.run(["sudo", "-n", "dmesg"], capture_output=True, text=True).stdout
    bad = [ln for ln in out.splitlines()
           if any(k in ln.lower() for k in ("amdgpu", "ring timeout", "gpu reset", "gpu hang"))
           and any(k in ln.lower() for k in ("error", "fail", "timeout", "reset", "hang"))]
    return len(bad)


def measure(cap):
    time.sleep(15)
    dec = [decode_rate() for _ in range(3)]
    med = statistics.median(d["tps"] for d in dec)
    best = max(dec, key=lambda d: d["tps"])
    pre = prefill_rate()
    row = {"cap": cap, "decode": round(med, 1), "decode_best": round(best["tps"], 1),
           "pmean": best["pmean"], "pmax": best["pmax"], "temp": best["tmax"],
           "prefill": pre["tps"], "pt": pre["pt"], "errors": gpu_errors(),
           "tokens": best["n"]}
    print(f"  {cap:>3} W  decode {row['decode']:5.1f} t/s  prefill {row['prefill']:7.1f} t/s  "
          f"{row['pmean']} W mean / {row['pmax']} W peak  {row['temp']} C  "
          f"errors={row['errors']}", flush=True)
    return row


print("== reset to the factory cap (baseline is taken with no write) ==", flush=True)
print("  before:", cap_now(), "W", flush=True)
print("  write 300 ->", write_cap(300), flush=True)
rows = [measure(300)]

for cap in MEASURE_CAPS[1:]:
    print(f"\n== cap {cap} W ==", flush=True)
    back, err = write_cap(cap)
    print(f"  write -> read-back {back} W {('| ' + err) if err else ''}", flush=True)
    rows.append(measure(cap))

print("\n== below the advertised floor (power1_cap_min = 210 W) ==", flush=True)
below = []
for cap in ATTEMPT_CAPS:
    back, err = write_cap(cap)
    ok = abs(back - cap) <= 1
    below.append({"asked": cap, "readback": back, "accepted": ok, "stderr": err})
    print(f"  asked {cap:>3} W -> card reports {back:>5.0f} W  "
          f"{'ACCEPTED' if ok else 'REFUSED'}"
          f"{(' | ' + err) if err else ''}", flush=True)
    if ok:
        r = measure(cap)
        rows.append(r)

print("\n== back to the working floor and hold it ==", flush=True)
back, err = write_cap(210)
print(f"  210 W -> {back} W {('| ' + err) if err else ''}", flush=True)

print("\n== stability: eight consecutive generations at the floor ==", flush=True)
rates, failures = [], 0
for i in range(8):
    try:
        r = decode_rate(512)
        rates.append(r["tps"])
        print(f"  run {i + 1}: {r['tps']:5.1f} t/s  {r['pmean']} W mean  {r['tmax']} C", flush=True)
    except Exception as e:  # noqa: BLE001
        failures += 1
        print(f"  run {i + 1}: FAILED {type(e).__name__}: {e}", flush=True)
    time.sleep(3)

base = rows[0]["decode"]
print("\n| cap W | decode t/s | vs 300 W | prefill t/s | power mean | power peak | junction | gpu errors |")
print("| ----: | ---------: | -------: | ----------: | ---------: | ---------: | -------: | ---------: |")
for r in rows:
    print(f"| {r['cap']:>5} | {r['decode']:10.1f} | {(r['decode'] - base) / base * 100:+6.1f} % | "
          f"{r['prefill']:11.1f} | {r['pmean']} W | {r['pmax']} W | {r['temp']} C | {r['errors']} |")

print(f"\nstability at 210 W: {len(rates)} runs, {failures} failures, "
      f"median {statistics.median(rates):.1f} t/s, min {min(rates):.1f}, max {max(rates):.1f}")
print("below-floor attempts:", json.dumps(below))
print("rows:", json.dumps(rows))
