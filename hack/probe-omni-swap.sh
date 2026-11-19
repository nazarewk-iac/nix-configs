#!/usr/bin/env bash
# Live probe: what happens to a loaded QFN when the omni companion is requested, and what a switch
# back costs. Read-only apart from the model loads it deliberately triggers.
set -u
SWAP=http://127.0.0.1:39700
MANAGER=http://127.0.0.1:8181
CARD=/sys/class/drm/card1/device

vram() { echo "$(($(cat $CARD/mem_info_vram_used) / 1073741824)) GiB"; }
status() {
  echo -n "  manager: "
  curl -s -m 5 "$MANAGER/status"
  echo
  echo -n "  vram:    "
  vram
  echo -n "  loaded:  "
  curl -s -m 8 "$SWAP/v1/models" | python3 -c '
import sys, json
d = json.load(sys.stdin)
rows = [(m["id"], (m.get("status") or {}).get("value")) for m in d["data"]]
print([r for r in rows if r[1] not in (None, "unloaded")] or "nothing")
'
}

ask() { # ask <alias>
  python3 - "$1" <<'PY'
import json, sys, time, urllib.request
alias = sys.argv[1]
body = json.dumps({
    "model": alias,
    "messages": [{"role": "user", "content": "Reply with the single word: ready"}],
    "max_tokens": 8,
    "stream": False,
}).encode()
req = urllib.request.Request("http://127.0.0.1:39700/v1/chat/completions", body,
                             {"Content-Type": "application/json"})
t0 = time.time()
try:
    with urllib.request.urlopen(req, timeout=1800) as r:
        d = json.load(r)
    print(f"  {alias}: {time.time() - t0:.1f}s -> {(d['choices'][0]['message'].get('content') or '').strip()!r}")
except Exception as e:  # noqa: BLE001
    print(f"  {alias}: FAILED after {time.time() - t0:.1f}s -> {type(e).__name__}: {e}")
PY
}

echo "=== 1. baseline (engine $MANAGER profile, nothing requested yet) ==="
status

echo
echo "=== 2. request the frontier alias chat-deep-slow (engine already on max) ==="
ask chat-deep-slow
status

echo
echo "=== 3. request the omni companion audio-std-mid while QFN holds the whole card ==="
ask audio-std-mid
status
echo "  swap log:"
sudo -n journalctl -u llama-swap --since "3 min ago" --no-pager 2>/dev/null |
  grep -iE "evict|swap|strata|surveyed|qwen3-omni|n_gpu_layers|CUDA|ROCm|failed|error" | tail -12 | cut -c1-170

echo
echo "=== 4. request chat-deep-slow again: is QFN still resident? ==="
ask chat-deep-slow
status

echo
echo "=== 5. switch the engine to omni-max while omni is loaded ==="
t0=$(date +%s%N)
curl -s -m 1200 -X POST "$MANAGER/select" -H 'Content-Type: application/json' \
  -d '{"profile":"omni-max"}' | head -c 200
t1=$(date +%s%N)
echo "  select omni-max: $(((t1 - t0) / 1000000)) ms"
status
echo
echo "=== 6. request omni now that the reserve exists ==="
ask audio-std-mid
status

echo
echo "=== 7. back to max: what the next frontier request costs ==="
t0=$(date +%s%N)
curl -s -m 1200 -X POST "$MANAGER/select" -H 'Content-Type: application/json' -d '{"profile":"max"}' | head -c 120
t1=$(date +%s%N)
echo "  select max: $(((t1 - t0) / 1000000)) ms"
ask chat-deep-slow
status
