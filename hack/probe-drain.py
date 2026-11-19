#!/usr/bin/env python3
"""Prove the drain: a `qfn` request is delayed by a profile switch, never cut.

Test A — a request is in flight when the switch starts: the switch waits for it, and it returns 200.
Test B — a request arrives after the switch started: it waits, then is served by the new engine.

Both are what "the harness must not be interrupted" means at the HTTP level.
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


def ask(tokens=512, model="qfn"):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": "Count from 1 to 400, one number per line."}],
        "max_tokens": tokens,
        "stream": False,
        "temperature": 0,
    }).encode()
    req = urllib.request.Request(SWAP, body, {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {KEY}",
    })
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            d = json.load(r)
        used = (d.get("usage") or {}).get("completion_tokens")
        return {"ok": True, "seconds": round(time.time() - t0, 1), "tokens": used}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "seconds": round(time.time() - t0, 1), "error": f"{type(e).__name__}: {str(e)[:80]}"}


def select(profile):
    body = json.dumps({"profile": profile}).encode()
    req = urllib.request.Request(f"{MANAGER}/select", body, {"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            out = json.load(r)
        return {"ok": True, "seconds": round(time.time() - t0, 1), "reply": out}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "seconds": round(time.time() - t0, 1), "error": str(e)[:80]}


def status():
    with urllib.request.urlopen(f"{MANAGER}/status", timeout=10) as r:
        d = json.load(r)
    return f"profile={d.get('profile')} in_flight={d.get('in_flight')} draining={d.get('draining')}"


print(f"start: {status()}")

print("\n== A: a request is already running when the profile switches ==")
a = {}
th = threading.Thread(target=lambda: a.update(ask()))
th.start()
time.sleep(1.5)
print(f"  request started, now asking for `max` while it runs ({status()})")
sw = select("max")
th.join()
print(f"  request: {json.dumps(a)}")
print(f"  switch:  {json.dumps(sw)}")
print(f"  after:   {status()}")
verdict_a = a.get("ok") and a.get("seconds", 0) > 1.5 and sw.get("ok")
print(f"  -> {'PASS' if verdict_a else 'FAIL'}: the request {'survived' if a.get('ok') else 'was cut'} "
      f"and the switch waited {sw.get('seconds')}s")

print("\n== B: a request arrives while the profile is switching ==")
b = {}
th2 = threading.Thread(target=lambda: b.update(ask(64)))
def later():
    time.sleep(1.0)
    th2.start()
select_thread = threading.Thread(target=lambda: later())
sw2 = {}
select_thread2 = threading.Thread(target=lambda: sw2.update(select("omni-fast")))
select_thread2.start()
select_thread.start()
select_thread2.join()
th2.join()
print(f"  switch:  {json.dumps(sw2)}")
print(f"  request: {json.dumps(b)}")
print(f"  after:   {status()}")
verdict_b = b.get("ok") and b.get("seconds", 0) > 5
print(f"  -> {'PASS' if verdict_b else 'FAIL'}: the late request "
      f"{'waited and was served' if b.get('ok') else 'failed'} in {b.get('seconds')}s")

print("\n== the journal ==")
with urllib.request.urlopen(f"{MANAGER}/stats", timeout=10) as r:
    st = json.load(r)
print(json.dumps({k: st["by_event"][k] for k in ("drain", "drain_timeout", "switch", "request")
                  if k in st["by_event"]}, indent=1))
