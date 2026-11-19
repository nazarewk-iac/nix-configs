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
# One JSON line per timed event. This is the record the switching skill is built from: every switch,
# every engine stop and load, every cache drop, every companion load and unload, each with the time
# it took. `GET /stats` aggregates it, so an agent can quote a measured cost instead of guessing.
EVENTS = f"{DATA}/strata/events.jsonl"
# The entries that proxy to the one engine on ENGINE_PORT. They must survive a profile switch: the
# port and the protocol do not change, only what the engine serves, and the entry whose request
# caused the switch is usually one of them.
FRONTIER_IDS = {
    "qfn",
    "qfn-max",
    "qfn-omni-max",
    "qfn-omni-fast",
    "chat-deep-slow",
    "code-deep-slow",
    "tools-deep-slow",
    "reason-deep-slow",
    "chat-deep-slow-omni",
    "chat-deep-slow-fast",
}
PORT = 8181
ENGINE_PORT = 8080
# A rough cost per profile, from the 2026-11-19 measurements: a reload plus the page-cache drop.
EXPECTED_SECONDS = {"max": 70, "omni-max": 70, "omni-fast": 55}
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


# llama-swap owns the companion processes, so the manager cannot time their loads directly. It
# polls llama-swap's view and records each transition with the interval it observed, which is
# accurate to the poll interval and honest about being observed rather than measured in-process.
COMPANIONS = {}
POLL_SECONDS = 3


def watch_companions():
    import urllib.request

    while True:
        time.sleep(POLL_SECONDS)
        try:
            with urllib.request.urlopen(f"{SWAP}/v1/models", timeout=5) as r:
                rows = json.load(r).get("data", [])
        except Exception:
            continue
        now = time.time()
        for m in rows:
            mid = m.get("id")
            if not mid or mid in FRONTIER_IDS:
                continue
            loaded = (m.get("status") or {}).get("value") == "loaded"
            prev = COMPANIONS.get(mid)
            if prev is None:
                COMPANIONS[mid] = {"loaded": loaded, "since": now}
                continue
            if loaded and not prev["loaded"]:
                # Time from the last sighting of "unloaded" to the first sighting of "loaded": the
                # load, accurate to the poll interval.
                event(
                    "companion_up",
                    model=mid,
                    seconds=round(now - prev["since"], 1),
                    observed=True,
                )
            elif not loaded and prev["loaded"]:
                # How long it stayed resident. The unload itself is faster than the poll interval,
                # so it is not a measurable duration here and is not reported as one.
                event(
                    "companion_down",
                    model=mid,
                    loaded_for=round(now - prev["since"], 1),
                    observed=True,
                )
            if loaded != prev["loaded"]:
                prev["loaded"] = loaded
                prev["since"] = now


def state():
    try:
        return json.load(open(STATE))
    except Exception:
        return {"profile": None}


def event(name, **fields):
    """Append one timed event. Never fail the operation because the record cannot be written."""
    rec = {"ts": round(time.time(), 3), "event": name, **fields}
    try:
        os.makedirs(os.path.dirname(EVENTS), exist_ok=True)
        with open(EVENTS, "a") as f:
            f.write(json.dumps(rec) + "\n")
    except Exception as e:  # noqa: BLE001
        print(f"strata-manager: event write failed: {e}", flush=True)


def read_events(limit=None):
    try:
        with open(EVENTS) as f:
            rows = [json.loads(ln) for ln in f if ln.strip()]
    except Exception:
        return []
    return rows[-limit:] if limit else rows


def last_switch():
    """The newest switch event, which `/status` reports so an agent can spot an unintended one."""
    for rec in reversed(read_events()):
        if rec.get("event") == "switch":
            return rec
    return None


def percentile(values, pct):
    if not values:
        return None
    ordered = sorted(values)
    idx = min(len(ordered) - 1, int(round((pct / 100.0) * (len(ordered) - 1))))
    return ordered[idx]


def stats():
    """Per-event and per-transition timings, from the journal this manager writes."""
    rows = read_events()
    by_event = {}
    by_transition = {}
    for r in rows:
        name = r.get("event")
        secs = r.get("seconds")
        if isinstance(secs, (int, float)):
            by_event.setdefault(name, []).append(secs)
        if name == "switch" and isinstance(secs, (int, float)):
            key = f"{r.get('from')}->{r.get('to')}"
            by_transition.setdefault(key, []).append(secs)

    def summarise(buckets):
        return {
            k: {
                "n": len(v),
                "median": percentile(v, 50),
                "p90": percentile(v, 90),
                "max": max(v),
            }
            for k, v in sorted(buckets.items())
        }

    return {
        "events": len(rows),
        "first_ts": rows[0]["ts"] if rows else None,
        "by_event": summarise(by_event),
        "by_transition": summarise(by_transition),
    }


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
    t0 = time.time()
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
    event("engine_stop", seconds=round(time.time() - t0, 1))


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
    t0 = time.time()
    deadline = t0 + 900
    while time.time() < deadline:
        if child.poll() is not None:
            event(
                "engine_load",
                profile=profile,
                seconds=round(time.time() - t0, 1),
                ok=False,
                error=f"exited with {child.returncode}",
            )
            return False, f"the engine exited with {child.returncode}"
        if engine_ready():
            event(
                "engine_load",
                profile=profile,
                seconds=round(time.time() - t0, 1),
                ok=True,
            )
            return True, f"pid {child.pid}"
        time.sleep(3)
    event(
        "engine_load",
        profile=profile,
        seconds=round(time.time() - t0, 1),
        ok=False,
        error="no answer in 900 s",
    )
    return False, "the engine did not answer within 900 s"


SWAP = "http://127.0.0.1:39700"


def unload(model=None):
    """Put a companion away without touching the engine.

    With no model this unloads every loaded model that is not a frontier entry, which is the call an
    agent makes after a vision or audio task. With a model it unloads that one, refusing a frontier
    entry: those proxies are how the engine is reached, so dropping one would break the next request
    rather than free VRAM.
    """
    import urllib.request

    t0 = time.time()
    if model is None:
        unload_companions()
        unloaded = "companions"
    elif model in FRONTIER_IDS:
        return {
            "ok": False,
            "error": f"{model!r} proxies to the engine; nothing to free",
        }
    else:
        try:
            req = urllib.request.Request(
                f"{SWAP}/api/models/unload/{model}", method="POST"
            )
            urllib.request.urlopen(req, timeout=120).read()
            unloaded = model
        except Exception as e:  # noqa: BLE001 - report, never crash the manager
            return {"ok": False, "error": f"{type(e).__name__}: {e}"}
    left = []
    try:
        with urllib.request.urlopen(f"{SWAP}/v1/models", timeout=10) as r:
            left = [
                m["id"]
                for m in json.load(r).get("data", [])
                if (m.get("status") or {}).get("value") == "loaded"
            ]
    except Exception:
        pass
    event(
        "companion_down",
        model=unloaded,
        seconds=round(time.time() - t0, 1),
        ok=True,
        cause="api",
    )
    return {"ok": True, "unloaded": unloaded, "still_loaded": left}


def tell_swap_to_unload():
    """Drop llama-swap's proxy children after a switch made outside llama-swap.

    **Only the companions.** Every frontier entry proxies to the one engine port, so its proxy stays
    valid across a profile switch — and unloading it kills the very request that asked for the
    switch (measured 2026-11-19: llama-swap sent the start command, the manager unloaded all models
    during the switch, and the client got a 500 ten milliseconds later). `qfn-*` and the deep
    aliases therefore stay loaded; the companion, which owns VRAM outside the engine, does not.
    """
    unload_companions()


def unload_companions():
    """Unload every loaded model that is not a frontier entry, and report what is left."""
    import urllib.request

    try:
        with urllib.request.urlopen(f"{SWAP}/v1/models", timeout=10) as r:
            loaded = [
                m["id"]
                for m in json.load(r).get("data", [])
                if (m.get("status") or {}).get("value") == "loaded"
            ]
    except Exception:
        return
    for mid in loaded:
        if mid in FRONTIER_IDS:
            continue
        try:
            req = urllib.request.Request(
                f"{SWAP}/api/models/unload/{mid}", method="POST"
            )
            urllib.request.urlopen(req, timeout=120).read()
            print(f"strata-manager: unloaded companion {mid}", flush=True)
        except Exception as e:  # noqa: BLE001 - a stuck companion must not block a switch
            print(f"strata-manager: unload {mid} failed: {e}", flush=True)


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
    t0 = time.time()
    try:
        p = subprocess.run(
            [SUDO, "-n", SYSTEMCTL, "start", "strata-drop-cache.service"],
            capture_output=True,
            text=True,
            timeout=300,
        )
        event(
            "cache_drop",
            seconds=round(time.time() - t0, 1),
            ok=p.returncode == 0,
        )
        if p.returncode != 0:
            print(
                f"strata-manager: cache drop failed ({p.returncode}): "
                f"{(p.stderr or '').strip()[:200]}",
                flush=True,
            )
    except Exception as e:  # noqa: BLE001 - never block a switch on the cache drop
        print(f"strata-manager: cache drop error: {e}", flush=True)


def select(profile, dry_run=False):
    with lock:
        cur = state().get("profile")
        if profile == "none":
            changed = cur not in (None, "none")
            if dry_run:
                return {
                    "dry_run": True,
                    "would_change": changed,
                    "current": cur,
                    "profile": "none",
                }
            t0 = time.time()
            tell_swap_to_unload()
            stop_engine()
            save({"profile": "none"})
            event(
                "switch",
                **{"from": cur},
                to="none",
                seconds=round(time.time() - t0, 1),
                ok=True,
                cause="select",
            )
            return {"changed": changed, "profile": "none"}
        if profile == cur:
            return {"changed": False, "profile": cur, "note": "already selected"}
        # `auto` is what a harness alias uses when the model name must not decide the engine: keep
        # whatever profile the manager holds and just report it. The profile is then set out of band
        # (`POST /select`, `brys-frontier.sh up --profile`), so picking a model in the agent harness
        # never triggers a reload.
        if profile == "auto":
            return {
                "changed": False,
                "profile": cur,
                "note": "auto: kept the current profile",
            }
        # A dry run answers "what would this cost" without touching the engine, so a caller can
        # decide whether a flip is worth it. The manager never decides for the caller: a profile
        # change is what somebody asked for.
        if dry_run:
            ls = last_switch()
            return {
                "dry_run": True,
                "would_change": True,
                "current": cur,
                "profile": profile,
                "expected_seconds": EXPECTED_SECONDS.get(profile, 60),
                "last_switch_seconds_ago": (
                    int(time.time() - ls["ts"]) if ls else None
                ),
                "last_switch": ls,
            }
        # Drop llama-swap's children **before** the reload, never after it. They keep a companion
        # resident (omni is about 17 GB of VRAM and 2 GB of RAM) and the incoming engine wants that
        # VRAM back; unloading first also resets llama-swap's view, which the switch has just
        # invalidated, so the next request re-selects instead of proxying to a stale port.
        t0 = time.time()
        tell_swap_to_unload()
        stop_engine()
        drop_caches()
        ok, out = start_engine(profile)
        elapsed = round(time.time() - t0)
        if not ok:
            save({"profile": None})
            event(
                "switch",
                **{"from": cur},
                to=profile,
                seconds=elapsed,
                ok=False,
                cause="select",
                error=out,
            )
            return {"error": out, "profile": None}
        save({"profile": profile})
        event(
            "switch",
            **{"from": cur},
            to=profile,
            seconds=elapsed,
            ok=True,
            cause="select",
        )
        return {"changed": True, "profile": profile, "seconds": elapsed}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            # The caller gave up while the manager was busy switching. Nothing to fix, and a
            # traceback per abandoned request would drown the journal.
            pass

    def do_GET(self):
        if self.path.startswith("/status"):
            ls = last_switch()
            body = dict(state())
            body["last_switch"] = ls
            body["last_switch_seconds_ago"] = (
                int(time.time() - ls["ts"]) if ls else None
            )
            # Only the loaded ones: the fleet has forty companion entries and listing them all
            # buries the answer. This is what an agent needs to see at a glance.
            body["loaded_companions"] = [
                m for m, v in COMPANIONS.items() if v["loaded"]
            ]
            self._send(200, body)
            return
        if self.path.startswith("/stats"):
            self._send(200, stats())
            return
        if self.path.startswith("/events"):
            limit = 100
            if "limit=" in self.path:
                try:
                    limit = int(self.path.split("limit=")[1].split("&")[0])
                except ValueError:
                    pass
            self._send(200, {"events": read_events(limit)})
            return
        self._send(404, {"error": "not found"})

    def do_POST(self):
        try:
            body = json.loads(
                self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}"
            )
        except Exception:
            return self._send(400, {"error": "body must be JSON"})
        if self.path.startswith("/unload"):
            try:
                self._send(200, unload(body.get("model")))
            except Exception as e:  # noqa: BLE001
                self._send(500, {"error": str(e)})
            return
        if not self.path.startswith("/select"):
            return self._send(404, {"error": "not found"})
        profile = body.get("profile")
        # `auto` keeps whatever profile the manager holds: it is what a harness alias uses when the
        # model name must not decide the engine.
        if profile not in ("max", "omni-max", "omni-fast", "auto", "none"):
            return self._send(400, {"error": f"unknown profile {profile!r}"})
        try:
            self._send(200, select(profile, dry_run=bool(body.get("dry_run"))))
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
    t0 = time.time()
    ok, out = start_engine(prof)
    print(f"strata-manager: restore {'ok' if ok else 'failed'}: {out}", flush=True)
    event(
        "switch",
        **{"from": None},
        to=prof,
        seconds=round(time.time() - t0, 1),
        ok=ok,
        cause="restore",
    )
    if ok:
        tell_swap_to_unload()
    else:
        save({"profile": None})


if __name__ == "__main__":
    print(f"strata-manager on :{PORT}", flush=True)
    threading.Thread(target=restore, daemon=True).start()
    threading.Thread(target=watch_companions, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
