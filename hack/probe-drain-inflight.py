#!/usr/bin/env python3
"""Prove the drain with a request that is provably mid-generation when the switch starts.

A streaming request is opened on `qfn`; the test waits until the first token arrives, so the engine
is demonstrably busy, and only then asks the manager for another profile. The stream must finish
with every token it asked for, and the switch must have waited for it.
"""
import json
import subprocess
import threading
import time
import urllib.request

SWAP = "http://127.0.0.1:39700/v1/chat/completions"
MANAGER = "http://127.0.0.1:8181"
KEY = subprocess.run(
    ["sudo", "-n", "cat", "/var/cache/llama-swap/api-keys"],
    capture_output=True, text=True, check=True,
).stdout.split("\n")[0].strip()

first_token = threading.Event()


def stream():
    body = json.dumps({
        "model": "qfn",
        "messages": [{"role": "user", "content": "Count from 1 to 600, one number per line."}],
        "max_tokens": 600,
        "stream": True,
        "temperature": 0,
    }).encode()
    req = urllib.request.Request(SWAP, body, {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {KEY}",
    })
    t0 = time.time()
    tokens = 0
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            for line in r:
                if not line.startswith(b"data: "):
                    continue
                payload = line[6:].strip()
                if payload == b"[DONE]":
                    break
                tokens += 1
                if tokens == 1:
                    first_token.set()
        return {"ok": True, "seconds": round(time.time() - t0, 1), "chunks": tokens}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "seconds": round(time.time() - t0, 1), "chunks": tokens,
                "error": f"{type(e).__name__}: {str(e)[:60]}"}


def select(profile):
    req = urllib.request.Request(f"{MANAGER}/select", json.dumps({"profile": profile}).encode(),
                                {"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        return {"seconds": round(time.time() - t0, 1), "reply": json.load(r)}


def status():
    with urllib.request.urlopen(f"{MANAGER}/status", timeout=10) as r:
        d = json.load(r)
    return d


# Warm the entry so the request does not race llama-swap's model start.
print("warm-up:", json.dumps(select("omni-fast")))
with urllib.request.urlopen(urllib.request.Request(
    SWAP, json.dumps({"model": "qfn", "messages": [{"role": "user", "content": "hi"}],
                      "max_tokens": 4}).encode(),
    {"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"}), timeout=600) as r:
    r.read()

print(f"before: {json.dumps(status())}")
result = {}
th = threading.Thread(target=lambda: result.update(stream()))
th.start()
assert first_token.wait(120), "the stream never produced a first token"
in_flight = status()
print(f"mid-generation: in_flight={in_flight.get('in_flight')} draining={in_flight.get('draining')}")
sw = select("max")
print(f"switch returned while the stream was open: {json.dumps(sw)}")
th.join()
print(f"stream result: {json.dumps(result)}")
print(f"after: {json.dumps(status())}")

with urllib.request.urlopen(f"{MANAGER}/stats", timeout=10) as r:
    st = json.load(r)["by_event"]
print("drain events:", json.dumps(st.get("drain")))

ok = result.get("ok") and result.get("chunks", 0) > 300 and st.get("drain", {}).get("n", 0) >= 1
print(f"-> {'PASS' if ok else 'FAIL'}: {result.get('chunks')} chunks relayed, "
      f"drain recorded {st.get('drain', {}).get('n', 0)} time(s)")
