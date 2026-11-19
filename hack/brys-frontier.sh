#!/usr/bin/env bash
# Drive the Strata profile manager on brys: switch the one engine, optionally for a bounded time.
#
# The manager (:8181) owns the engine. llama-swap's entries call `strata-select`, which asks the
# manager and then proxies; this script is the human and agent entry point to the same switch.
#
# Measured on the R9700, 2026-11-19 (docs/tasks/2026-11/brys-r9700-model-fit/measurements.md):
#
#   profile    pack + reserve                frontier decode        RAM left with it
#   max        UD-IQ4_XS, whole card         94.8-100.4 t/s short   2-3 GiB
#                                            73.1 t/s at 1M
#   omni-max   UD-IQ4_XS + 21.5 GB reserve   59.2-62.0 t/s short    3-5 GiB
#                                            42.3 t/s at 1M
#   omni-fast  IQ2_XS    + 21.5 GB reserve   88.3 t/s short         23-27 GiB
#                                            71.6 t/s at 1M
#
# The companion (qwen3-omni-30b-a3b, video and audio) answers at 96.9-98.8 t/s inside either
# reserve. Co-loaded beside `max` instead it gets about 1 GiB of VRAM and runs at 6.1 t/s, so a
# media request is worth a real switch, not a co-load.
#
# The resting profile is `omni-fast`: both models are reachable, and only it leaves RAM to spare.
# A `--ttl` loan flips to another profile and comes back by itself.
#
# Usage:
#   hack/brys-frontier.sh up                                   # select the resting profile
#   hack/brys-frontier.sh up --profile max --ttl 2h            # a quality session, then back
#   hack/brys-frontier.sh down                                 # stop the engine, free the card
#   hack/brys-frontier.sh status                               # profile, models, RAM, VRAM
set -uo pipefail

MANAGER=${STRATA_MANAGER:-127.0.0.1:8181}
RESTING=${STRATA_RESTING_PROFILE:-omni-fast}
PORT=${STRATA_PORT:-8080}
VRAM=/sys/class/drm/card1/device/mem_info_vram_used

profile=
ttl=
json=
action=${1:-status}
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
  --profile)
    profile=$2
    shift 2
    ;;
  --ttl)
    ttl=$2
    shift 2
    ;;
  --resting)
    RESTING=$2
    shift 2
    ;;
  --json)
    json=1
    shift
    ;;
  *)
    echo "unknown option: $1" >&2
    exit 2
    ;;
  esac
done
: "${profile:=$RESTING}"

select_profile() {
  curl -sS -m 1000 -X POST "http://$MANAGER/select" \
    -H 'Content-Type: application/json' -d "{\"profile\":\"$1\"}"
}

status() {
  local st
  st=$(curl -sS -m 5 "http://$MANAGER/status" 2>/dev/null) || st=''
  if [ -z "$st" ]; then
    echo "profile:  (manager not answering on $MANAGER)"
  else
    python3 - "$st" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
print(f"profile:  {d.get('profile')}")
ls = d.get("last_switch")
if ls:
    ago = d.get("last_switch_seconds_ago")
    ok = "" if ls.get("ok") else " FAILED"
    print(f"switch:   {ls.get('from')} -> {ls.get('to')} in {ls.get('seconds')}s, "
          f"{ago}s ago, cause={ls.get('cause')}{ok}")
else:
    print("switch:   none recorded yet")
PY
  fi
  echo -n "engine:   "
  curl -s -m 5 -o /dev/null -w "http %{http_code}\n" "http://127.0.0.1:$PORT/v1/models" 2>/dev/null ||
    echo "(not serving)"
  echo -n "models:   "
  curl -s -m 5 "http://127.0.0.1:39700/v1/models" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print([m['id'] for m in d['data'] if (m.get('status') or {}).get('value') == 'loaded'] or 'none')
" 2>/dev/null || echo "(llama-swap not answering)"
  echo "vram:     $(($(cat "$VRAM") / 1073741824)) GiB of 31.8"
  free -g | sed -n 2p | sed 's/^/ram:      /'
}

case "$action" in
up)
  reply=$(select_profile "$profile") || {
    echo "the manager is not answering on $MANAGER" >&2
    exit 1
  }
  echo "select $profile -> $reply"
  # A timed loan: a transient systemd unit reverts to the resting profile when the TTL runs out. It
  # lives outside the manager on purpose, so a manager restart cannot drop the revert and a failing
  # revert cannot hold the manager's lock (the failure mode of an in-process timer).
  if [ -n "$ttl" ]; then
    sudo -n systemctl stop strata-revert 2>/dev/null || true
    sudo -n systemd-run --unit=strata-revert --on-active="$ttl" --collect \
      -- curl -sS -m 900 -X POST "http://$MANAGER/select" \
      -H 'Content-Type: application/json' -d "{\"profile\":\"$RESTING\"}" >/dev/null
    echo "scheduled: back to $RESTING in $ttl (unit strata-revert)"
  fi
  ;;
down)
  select_profile none
  echo
  ;;
status)
  if [ -n "$json" ]; then
    # One object for an agent to parse: the manager's own view plus the llama-swap view.
    curl -sS -m 5 "http://$MANAGER/status" || echo '{"error":"manager not answering"}'
    echo
    exit 0
  fi
  status
  ;;
*)
  echo "usage: $0 {up|down|status} [--profile max|omni-max|omni-fast|none] [--ttl 30m] [--resting <profile>]" >&2
  exit 2
  ;;
esac
