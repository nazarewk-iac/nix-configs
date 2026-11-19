#!/usr/bin/env python3
"""The Strata profile manager for brys.

Why this exists: a Strata profile differs from another only in engine start-up arguments (VRAM
reserve, KV residency, pack), so llama-swap cannot switch between them without a full 55 GiB
reload. It also has no `none` state. This service owns one engine and answers `/select`:

  POST /select {"profile": "max"}        -> starts or switches only if the profile differs
  POST /select {"profile": "none"}       -> stops the engine, freeing the card
  GET  /status                           -> the current profile, readiness and pid

The llama-swap entries do not own the engine: their `cmd` calls `strata-select`, which asks this
service and then proxies llama-swap's port to the engine. Switching between two llama-swap entries
that resolve to the same profile therefore costs one TCP proxy, not a model reload.

Measured on the R9700 (docs/tasks/2026-11/brys-r9700-model-fit/measurements.md):
  same profile      0 s   (no engine action at all)
  different profile 47-180 s (engine reload, warm page cache)
  none              2-5 s (drain and stop)
"""

import json
import os
import time
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STRATA = "/var/lib/kdn/llms/models/.bench/bin/strata"
DATA = "/var/lib/kdn/llms/models/.bench/xdg"
PROFILES = f"{DATA}/strata/profiles"
STATE = f"{DATA}/strata/manager-state.json"
PORT = 8181
ENGINE_PORT = 8080
# One sudoers-named command: the cache drop is the only privileged action the manager takes.
SUDO = "/run/wrappers/bin/sudo"
SYSTEMCTL = "/run/current-system/sw/bin/systemctl"

ENV = dict(
    os.environ,
    HOME="/var/lib/kdn/llms/home",
    XDG_DATA_HOME=DATA,
    STRATA_DATA_HOME=DATA,
)
# The shim is only needed while the RX 550 is in the box; its absence is not fatal on 0.1.62.
SHIM = "/var/lib/kdn/llms/models/.bench/rocm-skip.so"
if os.access(SHIM, os.R_OK):
    ENV["LD_PRELOAD"] = SHIM

lock = threading.Lock()


def state():
    try:
        return json.load(open(STATE))
    except Exception:
        return {"profile": None}


def save(s):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    json.dump(s, open(STATE, "w"))


def run(args, timeout=900):
    p = subprocess.run(
        [STRATA, *args], env=ENV, capture_output=True, text=True, timeout=timeout
    )
    return p.returncode, (p.stdout or "") + (p.stderr or "")


child = None


def engine_ready(timeout=2):
    import urllib.request

    try:
        urllib.request.urlopen(
            f"http://127.0.0.1:{ENGINE_PORT}/v1/models", timeout=timeout
        ).read()
        return True
    except Exception:
        return False


def stop_engine():
    """Stop the engine this manager started; leave an engine it does not own alone."""
    global child
    if child is not None and child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=180)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait(timeout=30)
    child = None
    # A previous manager instance may have left one behind; `serve` has no PID file of its own.
    run(["launch", "--stop"], timeout=300)


def start_engine(profile):
    """Start `strata serve` for one profile and block until it answers, or fail."""
    global child
    cfg = f"{PROFILES}/strata-{profile}.json"
    if not os.path.exists(cfg):
        return (
            False,
            f"no profile config at {cfg}; run `strata serve --profile` once for it",
        )
    child = subprocess.Popen(
        [
            STRATA,
            "serve",
            "--profile",
            cfg,
            "--host",
            "127.0.0.1",
            "--port",
            str(ENGINE_PORT),
        ],
        env=ENV,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 900
    while time.time() < deadline:
        if child.poll() is not None:
            return False, f"the engine exited with {child.returncode}"
        if engine_ready():
            return True, f"pid {child.pid}"
        time.sleep(3)
    return False, "the engine did not answer within 900 s"


def tell_swap_to_unload():
    """Drop llama-swap's proxy children after a switch made outside llama-swap.

    A switch through the manager bypasses llama-swap's bookkeeping: its entries would keep a proxy
    pointed at a port the engine no longer serves the same way, and `/v1/models` would report the
    previous profile as loaded. Unloading resets that view; the next request re-selects, which is a
    no-op because the manager's own state is already correct.
    """
    import urllib.request

    try:
        req = urllib.request.Request(
            "http://127.0.0.1:39700/api/models/unload", method="POST"
        )
        urllib.request.urlopen(req, timeout=10).read()
    except Exception:
        pass


def drop_caches():
    """Release the pack's page cache before a load.

    The load is a ~95 GiB burst on a 125 GiB host with no swap. With 40-48 GiB of the pack still
    cached, reclaim cannot keep up and the kernel OOM-kills the engine mid-load (measured
    2026-11-19: every failing load ended at 88-98 GiB RSS with `free` at zero, while the same
    profile loaded fine on a fresh boot). The cache is the cheap side of the trade: the pool reads
    the pack back at 7.7 GB/s, so the drop costs seconds and returns tens of GiB.

    The write needs root, so it goes through one sudoers-named unit. A failure here is reported and
    ignored: a load without the drop should still be attempted.
    """
    try:
        p = subprocess.run(
            [SUDO, "-n", SYSTEMCTL, "start", "strata-drop-cache.service"],
            capture_output=True,
            text=True,
            timeout=300,
        )
        if p.returncode != 0:
            print(
                f"strata-manager: cache drop failed ({p.returncode}): "
                f"{(p.stderr or '').strip()[:200]}",
                flush=True,
            )
    except Exception as e:  # noqa: BLE001 - never block a switch on the cache drop
        print(f"strata-manager: cache drop error: {e}", flush=True)


def select(profile):
    with lock:
        cur = state().get("profile")
        if profile == "none":
            changed = cur not in (None, "none")
            tell_swap_to_unload()
            stop_engine()
            save({"profile": "none"})
            return {"changed": changed, "profile": "none"}
        if profile == cur:
            return {"changed": False, "profile": cur, "note": "already selected"}
        # Drop llama-swap's children **before** the reload, never after it. They keep a companion
        # resident (omni is about 17 GB of VRAM and 2 GB of RAM) and the incoming engine wants that
        # VRAM back; unloading first also resets llama-swap's view, which the switch has just
        # invalidated, so the next request re-selects instead of proxying to a stale port.
        tell_swap_to_unload()
        stop_engine()
        drop_caches()
        ok, out = start_engine(profile)
        if not ok:
            save({"profile": None})
            return {"error": out, "profile": None}
        save({"profile": profile})
        return {"changed": True, "profile": profile}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.startswith("/status"):
            self._send(200, state())
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self.path.startswith("/select"):
            return self._send(404, {"error": "not found"})
        try:
            body = json.loads(
                self.rfile.read(int(self.headers.get("Content-Length") or 0))
            )
        except Exception:
            return self._send(400, {"error": "body must be JSON"})
        profile = body.get("profile")
        if profile not in ("max", "omni-max", "omni-fast", "none"):
            return self._send(400, {"error": f"unknown profile {profile!r}"})
        try:
            self._send(200, select(profile))
        except Exception as e:  # noqa: BLE001 - report, never crash the manager
            self._send(500, {"error": str(e)})

    def log_message(self, fmt, *a):
        sys.stderr.write("strata-manager: " + fmt % a + "\n")


def restore():
    """Bring back the profile the last run left selected.

    The manager's child dies with the service, so a restart (a switch, a crash) would otherwise
    leave the state file claiming a profile that nothing serves. Restoring also makes `max` the
    default at boot without a separate unit.
    """
    prof = state().get("profile")
    if prof in (None, "none"):
        return
    if engine_ready():
        return
    print(f"strata-manager: restoring profile {prof}", flush=True)
    ok, out = start_engine(prof)
    print(f"strata-manager: restore {'ok' if ok else 'failed'}: {out}", flush=True)
    if ok:
        tell_swap_to_unload()
    else:
        save({"profile": None})


if __name__ == "__main__":
    print(f"strata-manager on :{PORT}", flush=True)
    threading.Thread(target=restore, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
