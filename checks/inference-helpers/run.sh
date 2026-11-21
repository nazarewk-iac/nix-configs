#!/usr/bin/env bash
# The runtime end to end with one 1 MB model and no GPU.
#
# Starts the real processes — the manager, one `select` proxy and one `gate` — and drives them over
# loopback with a python client:
#
#   1. the first request through `select` starts the engine on `max`
#   2. a second request through `select` must not switch it
#   3. the gated model with no reserve answers 409 and names its own remedy
#   4. the same request with `kdn_switch_to` switches the engine and serves
#
# llama-swap is deliberately not part of this check: its own scheduler (health gating, per-entry
# start/stop) is what kills a cold-starting entry inside the sandbox, and that behaviour is llama-swap's
# contract, not ours. The revert-on-unload is covered by the Go unit test against a fake accessory.
set -euo pipefail

: "${MODEL:?}" "${LLAMA:?}" "${HELPERS:?}" "${WORK:?}"
MANAGER_PORT=18181
ENGINE_PORT=18080
SELECT_PORT=18090
GATE_PORT=18091
export HOME="$WORK/home"
mkdir -p "$HOME" "$WORK/data/strata/profiles"

CONFIG="$WORK/config.json"
cat >"$CONFIG" <<EOF
{
  "engine": "command",
  "dataDir": "$WORK/data",
  "enginePort": $ENGINE_PORT,
  "managerPort": $MANAGER_PORT,
  "swapURL": "http://127.0.0.1:1",
  "aliases": { "qfn": "auto", "qfn-max": "max", "qfn-fast-colo": "omni-fast" },
  "frontierIDs": ["qfn", "qfn-max", "qfn-fast-colo"],
  "textProfiles": ["max"],
  "cacheDropCommand": [],
  "engineLog": "$WORK/data/strata/engine.log",
  "drainTimeoutSeconds": 60,
  "leaseTTLSeconds": 600,
  "gates": {
    "tiny-omni": {
      "requireProfiles": ["omni-fast"],
      "allow": ["omni-fast"],
      "confirmField": "kdn_switch_to"
    }
  },
  "commands": {
    "max":       ["$LLAMA", "--model", "$MODEL", "--host", "127.0.0.1", "--ctx-size", "512", "--parallel", "1"],
    "omni-fast": ["$LLAMA", "--model", "$MODEL", "--host", "127.0.0.1", "--ctx-size", "512", "--parallel", "1"]
  }
}
EOF

"$HELPERS" manager --config "$CONFIG" >"$WORK/manager.log" 2>&1 &
MANAGER_PID=$!
"$HELPERS" select qfn --port "$SELECT_PORT" --config "$CONFIG" >"$WORK/select.log" 2>&1 &
SELECT_PID=$!
"$HELPERS" gate --name tiny-omni --config "$CONFIG" -- \
  "$LLAMA" --model "$MODEL" --host 127.0.0.1 --port "$GATE_PORT" --ctx-size 512 --parallel 1 \
  >"$WORK/gate.log" 2>&1 &
GATE_PID=$!
cleanup() { kill "$GATE_PID" "$SELECT_PID" "$MANAGER_PID" 2>/dev/null || true; }
trap cleanup EXIT

cd "$WORK"
python3 - "$MANAGER_PORT" "$SELECT_PORT" "$GATE_PORT" <<'PY'
import json, sys, time, traceback, urllib.error, urllib.request

manager, select_port, gate_port = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])


def wait(url, tries=120):
    for _ in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=2):
                return
        except Exception:
            time.sleep(0.5)
    raise SystemExit(f"never answered: {url}")


def post(url, body, timeout=240):
    req = urllib.request.Request(url, json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw or b"{}")
        except json.JSONDecodeError:
            return e.code, {"raw": raw.decode(errors="replace")}


def status():
    with urllib.request.urlopen(f"http://127.0.0.1:{manager}/status", timeout=5) as r:
        return json.load(r)


def switches():
    with urllib.request.urlopen(f"http://127.0.0.1:{manager}/stats", timeout=5) as r:
        return json.load(r)["by_event"].get("switch", {}).get("n", 0)


def ask(port, extra=None, tokens=8):
    body = {"model": "qfn", "messages": [{"role": "user", "content": "say ok"}], "max_tokens": tokens}
    body.update(extra or {})
    return post(f"http://127.0.0.1:{port}/v1/chat/completions", body)


def dump():
    for log in ("manager.log", "select.log", "gate.log"):
        try:
            print(f"--- {log} ---")
            print(open(log).read()[-4000:])
        except OSError:
            pass


wait(f"http://127.0.0.1:{manager}/status")
# `select` asks the manager for its profile first and only then binds, so waiting for its port is
# also the assertion that the startup switch happened.
wait(f"http://127.0.0.1:{select_port}/v1/models")

try:
    # 1. the proxy's startup switch put the engine on the whole-card profile
    assert status()["profile"] == "max", status()
    code, body = ask(select_port)
    assert code == 200, (code, body)
    assert status()["profile"] == "max", status()
    after_first = switches()

    # 2. a second request must not switch anything
    code, _ = ask(select_port)
    assert code == 200, code
    assert switches() == after_first, "a second request switched the engine"

    # 3. the gated model with no reserve answers 409 and names its own remedy
    code, body = ask(gate_port)
    assert code == 409, (code, body)
    assert body["confirm"]["field"] == "kdn_switch_to", body
    assert body["alternatives"] == ["omni-fast"], body
    attempts = switches()

    # 4. the same request with the confirm field switches and serves
    code, body = ask(gate_port, {"kdn_switch_to": "qfn-fast-colo"})
    assert code == 200, (code, body)
    assert status()["profile"] == "omni-fast", status()
    assert switches() > attempts, "the confirmed request did not switch the engine"

    # 5. a gated request while the reserve is present is served without a switch
    settled = switches()
    code, _ = ask(gate_port)
    assert code == 200, code
    assert switches() == settled, "a gated request switched the engine while the reserve was active"
except Exception:
    traceback.print_exc()
    dump()
    raise

print("inference runtime integration: PASS")
PY
