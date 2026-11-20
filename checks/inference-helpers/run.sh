#!/usr/bin/env bash
# The runtime end to end with one 1 MB model and no GPU.
#
# Starts the manager with the `command` adapter (each profile is just a llama-server), llama-swap
# with two entries (a QFN proxy and the companion gate), and drives the real request paths:
#
#   1. the first `qfn` request starts the engine on `max`
#   2. a second `qfn` request must not switch it
#   3. asking for the companion with no reserve answers 409 and names its own remedy
#   4. the same request with `kdn_switch_to` switches and serves
#   5. unloading the companion returns the engine to `max` by itself
#
# Everything is loopback, under a second per engine start, and it proves the wiring that the Go unit
# tests cannot: ports, config file, process hand-off, llama-swap's `cmd` contract.
set -euo pipefail

: "${MODEL:?}" "${LLAMA:?}" "${HELPERS:?}" "${SWAP_BIN:?}" "${WORK:?}"
MANAGER_PORT=18181
ENGINE_PORT=18080
SWAP_PORT=18700
export HOME="$WORK/home"
mkdir -p "$HOME" "$WORK/data/strata/profiles"

CONFIG="$WORK/config.json"
cat >"$CONFIG" <<EOF
{
  "engine": "command",
  "dataDir": "$WORK/data",
  "enginePort": $ENGINE_PORT,
  "managerPort": $MANAGER_PORT,
  "swapURL": "http://127.0.0.1:$SWAP_PORT",
  "aliases": { "qfn": "auto", "qfn-max": "max", "qfn-fast-colo": "omni-fast" },
  "frontierIDs": ["qfn", "qfn-max", "qfn-fast-colo"],
  "cacheDropCommand": [],
  "engineLog": "$WORK/data/strata/engine.log",
  "drainTimeoutSeconds": 60,
  "leaseTTLSeconds": 600,
  "gates": {
    "tiny-omni": { "requireProfiles": ["omni-fast"], "allow": ["omni-fast"], "confirmField": "kdn_switch_to" }
  },
  "commands": {
    "max":       ["$LLAMA", "--model", "$MODEL", "--host", "127.0.0.1", "--ctx-size", "512", "--parallel", "1"],
    "omni-fast": ["$LLAMA", "--model", "$MODEL", "--host", "127.0.0.1", "--ctx-size", "512", "--parallel", "1"]
  }
}
EOF

SWAP="$WORK/swap.yaml"
cat >"$SWAP" <<EOF
healthCheckTimeout: 120
logLevel: warn
models:
  tiny:
    cmd: $HELPERS select qfn --port \${PORT} --config $CONFIG
  tiny-omni:
    cmd: $HELPERS gate --name tiny-omni --config $CONFIG -- $LLAMA --model $MODEL --host 127.0.0.1 --port \${PORT} --ctx-size 512 --parallel 1
EOF

"$HELPERS" manager --config "$CONFIG" >"$WORK/manager.log" 2>&1 &
MANAGER_PID=$!
"$SWAP_BIN" --config "$SWAP" --listen "127.0.0.1:$SWAP_PORT" >"$WORK/swap.log" 2>&1 &
SWAP_PID=$!
cleanup() { kill "$SWAP_PID" "$MANAGER_PID" 2>/dev/null || true; }
trap cleanup EXIT

python3 - "$MANAGER_PORT" "$SWAP_PORT" "$SWAP_PORT" <<'PY'
import json, sys, time, urllib.error, urllib.request

manager, swap = int(sys.argv[1]), int(sys.argv[2])


def wait(url, tries=120):
    for _ in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=2) as r:
                return True
        except Exception:
            time.sleep(0.5)
    raise SystemExit(f"never answered: {url}")


def post(url, body, timeout=180):
    req = urllib.request.Request(url, json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def profile():
    with urllib.request.urlopen(f"http://127.0.0.1:{manager}/status", timeout=5) as r:
        return json.load(r)


def switches():
    with urllib.request.urlopen(f"http://127.0.0.1:{manager}/stats", timeout=5) as r:
        return json.load(r)["by_event"].get("switch", {}).get("n", 0)


def ask(model, extra=None, tokens=8):
    body = {"model": model, "messages": [{"role": "user", "content": "say ok"}], "max_tokens": tokens}
    body.update(extra or {})
    return post(f"http://127.0.0.1:{swap}/v1/chat/completions", body)


wait(f"http://127.0.0.1:{manager}/status")
wait(f"http://127.0.0.1:{swap}/v1/models")

# 1. the first `qfn` request starts the engine on max
status, body = ask("tiny")
assert status == 200, (status, body)
assert profile()["profile"] == "max", profile()
after_first = switches()

# 2. a second `qfn` request must not switch anything
status, _ = ask("tiny")
assert status == 200
assert switches() == after_first, "a second qfn request switched the engine"

# 3. the companion with no reserve answers 409 with its own remedy
status, body = ask("tiny-omni")
assert status == 409, (status, body)
assert body["confirm"]["field"] == "kdn_switch_to", body
assert body["requires"] == "colo", body
attempts = switches()

# 4. the same request with kdn_switch_to switches and serves
status, body = ask("tiny-omni", {"kdn_switch_to": "qfn-fast-colo"})
assert status == 200, (status, body)
assert profile()["profile"] == "omni-fast", profile()
assert switches() > attempts, "the confirmed request did not switch the engine"

# 5. unloading the companion returns the engine to max by itself
post(f"http://127.0.0.1:{swap}/api/models/unload/tiny-omni", {})
deadline = time.time() + 120
while time.time() < deadline:
    if profile()["profile"] == "max":
        break
    time.sleep(1)
assert profile()["profile"] == "max", f"the engine did not revert: {profile()}"

print("inference runtime integration: PASS")
PY
