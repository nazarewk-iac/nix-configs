#!/usr/bin/env python3
"""Decode rates per mode, with the model load separated from the generation.

Every rate below is the *second* request against an already-loaded model, so it measures decode
only. The first request is printed too: its extra time is the load (or a cold expert cache).
"""
import json
import subprocess
import time
import urllib.request

SWAP = "http://127.0.0.1:39700/v1/chat/completions"
MANAGER = "http://127.0.0.1:8181/select"
CARD = "/sys/class/drm/card1/device/mem_info_vram_used"
KEY = subprocess.run(
    ["sudo", "-n", "cat", "/var/cache/llama-swap/api-keys"],
    capture_output=True, text=True, check=True,
).stdout.split("\n")[0].strip()

PROMPT = "Write the numbers 1 to 200 as digits separated by commas."


def host():
    vram = int(open(CARD).read()) / 2**30
    mem = {}
    for line in open("/proc/meminfo"):
        k, v = line.split(":", 1)
        mem[k] = int(v.split()[0]) / 2**20
    return (f"vram={vram:4.0f}G used={mem['MemTotal'] - mem['MemAvailable']:3.0f}G "
            f"avail={mem['MemAvailable']:3.0f}G")


def ask(model, tokens):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": PROMPT}],
        "max_tokens": tokens,
        "stream": False,
        "temperature": 0,
    }).encode()
    req = urllib.request.Request(SWAP, body, {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {KEY}",
    })
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        d = json.load(r)
    dt = time.time() - t0
    n = (d.get("usage") or {}).get("completion_tokens") or tokens
    return dt, n


def rate(model, tokens):
    t_load, _ = ask(model, tokens)
    t_run, n = ask(model, tokens)
    return f"first {t_load:6.1f}s | warm {n:3d} tok in {t_run:5.2f}s -> {n / t_run:5.1f} t/s"


def select(profile):
    req = urllib.request.Request(MANAGER, json.dumps({"profile": profile}).encode(),
                                 {"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        out = json.load(r)
    return f"{time.time() - t0:5.0f}s {out}"


print("== mode A: resting on `max` (UD-IQ4_XS, whole card, no reserve) ==")
print(f"   host {host()}")
print(f"   QFN  {rate('chat-deep-slow', 96)}")
print(f"   host {host()}")
print("   omni requested beside it, no profile switch:")
print(f"   omni {rate('audio-std-mid', 32)}")
print(f"   host {host()}")
print(f"   QFN  {rate('chat-deep-slow', 96)}  (after the companion took its VRAM)")

print()
print("== mode B: resting on `omni-fast` (IQ2_XS + 21.5 GB reserve) ==")
print(f"   select {select('omni-fast')}")
print(f"   host {host()}")
print(f"   QFN  {rate('chat-deep-slow-fast', 96)}")
print(f"   omni {rate('audio-std-mid', 32)}")
print(f"   host {host()}")

print()
print("== mode C: back to `max` (the same pack, whole card again) ==")
print(f"   select {select('max')}")
print(f"   host {host()}")
print(f"   QFN  {rate('chat-deep-slow', 96)}")
print(f"   host {host()}")
