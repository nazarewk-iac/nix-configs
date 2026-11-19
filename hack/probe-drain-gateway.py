#!/usr/bin/env python3
"""The in-flight guarantee, through the gateway instead of brys directly.

OpenCode and Pi reach brys through LiteLLM on etra, so a switch now has to survive that hop too:
LiteLLM's per-deployment `stream_timeout` must be longer than the switch, and its own buffering
must not choke on a pause. This opens a streaming `qfn` request through the gateway, waits for the
first token, switches the profile underneath it, and checks that the stream finishes.
"""
import json
import os
import subprocess
import threading
import time
import urllib.request

GW = "https://litellm.etra.priv.nb.net.int.kdn.im/v1/chat/completions"
MANAGER_SSH = "brys"
KEY = subprocess.run(
    ["sudo", "-n", "cat", "/run/configs/llms/litellm/client-key"],
    capture_output=True, text=True, check=True,
).stdout.strip()

first = threading.Event()


def stream():
    body = json.dumps({
        "model": "qfn",
        "messages": [{"role": "user", "content": "Count from 1 to 500, one number per line."}],
        "max_tokens": 500,
        "stream": True,
        "temperature": 0,
    }).encode()
    req = urllib.request.Request(GW, body, {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {KEY}",
    })
    t0, chunks = time.time(), 0
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            for line in r:
                if line.startswith(b"data: ") and line.strip() != b"data: [DONE]":
                    chunks += 1
                    if chunks == 1:
                        first.set()
        return {"ok": True, "seconds": round(time.time() - t0, 1), "chunks": chunks}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "seconds": round(time.time() - t0, 1), "chunks": chunks,
                "error": f"{type(e).__name__}: {str(e)[:70]}"}


def ssh(cmd):
    return subprocess.run(["ssh", "-o", "BatchMode=yes", MANAGER_SSH, cmd],
                          capture_output=True, text=True).stdout.strip()


def select(profile):
    t0 = time.time()
    out = ssh(f"curl -s -m 900 -X POST http://127.0.0.1:8181/select "
              f"-H 'Content-Type: application/json' -d '{{\"profile\":\"{profile}\"}}'")
    return {"seconds": round(time.time() - t0, 1), "reply": out}


print("profile before:", ssh("curl -s -m 5 http://127.0.0.1:8181/status"))
res = {}
th = threading.Thread(target=lambda: res.update(stream()))
th.start()
if not first.wait(180):
    print("FAIL: no first token through the gateway")
    raise SystemExit(1)
print(f"first token through the gateway; switching the profile underneath it")
sw = select("qfn-max")   # the profile `qfn-max` names; current is omni-fast
th.join()
print("stream:", json.dumps(res))
print("switch:", json.dumps(sw))
print("profile after:", ssh("curl -s -m 5 http://127.0.0.1:8181/status"))
print("->", "PASS" if res.get("ok") and res.get("chunks", 0) > 300 else "FAIL")
