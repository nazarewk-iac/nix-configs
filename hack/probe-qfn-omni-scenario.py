#!/usr/bin/env python3
"""Walk the real-world scenario and let the manager's event journal time every step.

  coding on QFN  ->  screenshot needs omni  ->  omni loads beside the engine  ->  work resumes
  ->  omni unloaded  ->  back to the highest-quality QFN

Every step prints what the manager reports, and the last block prints the aggregate timings it
recorded. Nothing here switches a model on purpose except the two profile calls at the ends.
"""
import json
import subprocess
import time
import urllib.request

SWAP = "http://127.0.0.1:39700"
MANAGER = "http://127.0.0.1:8181"
KEY = subprocess.run(
    ["sudo", "-n", "cat", "/var/cache/llama-swap/api-keys"],
    capture_output=True, text=True, check=True,
).stdout.split("\n")[0].strip()


def get(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def post(url, body=None):
    data = json.dumps(body or {}).encode()
    req = urllib.request.Request(url, data, {"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        out = json.load(r)
    return round(time.time() - t0, 1), out


def ask(model, tokens=24, content="Count from 1 to 30 in words."):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "max_tokens": tokens,
        "stream": False,
        "temperature": 0,
    }).encode()
    req = urllib.request.Request(f"{SWAP}/v1/chat/completions", body, {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {KEY}",
    })
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            d = json.load(r)
        used = (d.get("usage") or {}).get("completion_tokens") or tokens
        return f"{round(time.time() - t0, 1)}s, {used} tok"
    except Exception as e:  # noqa: BLE001
        return f"FAILED {round(time.time() - t0, 1)}s {type(e).__name__}: {str(e)[:60]}"


def status(tag):
    st = get(f"{MANAGER}/status")
    print(f"  [{tag}] profile={st.get('profile')} companions={st.get('loaded_companions')} "
          f"last_switch={st.get('last_switch', {}).get('from')}->{st.get('last_switch', {}).get('to')} "
          f"in {st.get('last_switch', {}).get('seconds')}s")


print("== 1. a coding turn on the current engine (`max`), through the profile-neutral alias ==")
status("before")
print(f"  chat-deep-slow: {ask('chat-deep-slow')}")
status("after")

print()
print("== 2. what a switch to `omni-fast` would cost, without doing it ==")
dt, out = post(f"{MANAGER}/select", {"profile": "omni-fast", "dry_run": True})
print(f"  dry run ({dt}s): {json.dumps(out)}")

print()
print("== 3. take the reserve so the screenshot can be read ==")
dt, out = post(f"{MANAGER}/select", {"profile": "omni-fast"})
print(f"  switch ({dt}s): {json.dumps(out)}")
status("after switch")

print()
print("== 4. the screenshot: omni loads beside the engine ==")
print(f"  audio-std-mid: {ask('audio-std-mid', 16, 'Describe what you see in one sentence.')}")
status("omni up")
print(f"  chat-deep-slow again: {ask('chat-deep-slow')}   (engine untouched?)")
status("coding resumed")

print()
print("== 5. issue resolved: put omni away, engine keeps running ==")
dt, out = post(f"{MANAGER}/unload")
print(f"  unload ({dt}s): {json.dumps(out)}")
time.sleep(5)
status("omni down")

print()
print("== 6. back to the highest-quality QFN ==")
dt, out = post(f"{MANAGER}/select", {"profile": "max"})
print(f"  switch ({dt}s): {json.dumps(out)}")
print(f"  chat-deep-slow: {ask('chat-deep-slow')}")
status("final")

print()
print("== 7. what the journal learned ==")
print(json.dumps(get(f"{MANAGER}/stats"), indent=2))
