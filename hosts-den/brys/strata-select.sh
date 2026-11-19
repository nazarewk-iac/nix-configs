#!/usr/bin/env bash
# One llama-swap entry point per Strata profile.
#
# It asks the manager to make the profile current (which is a no-op when it already is), then
# proxies llama-swap's port to the engine on 8080. llama-swap therefore pays a TCP proxy per
# switch and a model reload only when the profile really changed.
#
# Usage: strata-select <max|omni-max|omni-fast> --port N
set -uo pipefail

profile=${1:?profile required}; shift || true
port=8080
while [ $# -gt 0 ]; do
  case "$1" in
    --port) port=$2; shift 2 ;;
    *) shift ;;
  esac
done

engine=8080
manager=127.0.0.1:8181

# Ask the manager; it starts, switches or declines. A failure here must not leave a proxy in front
# of a dead engine, so it exits non-zero and llama-swap reports the model as failed.
reply=$(curl -sS -m 1000 -X POST "http://$manager/select" \
  -H 'Content-Type: application/json' -d "{\"profile\":\"$profile\"}") || {
  echo "strata-select: the manager is not answering on $manager" >&2
  exit 1
}
case "$reply" in
  *'"error"'*) echo "strata-select: $reply" >&2; exit 1 ;;
esac
echo "strata-select: $profile -> $reply" >&2

# The engine is up; forward this port to it for as long as llama-swap keeps this model loaded.
# A dual-stack listener, because llama-swap resolves `localhost` to ::1 first.
exec "${STRATA_PROXY:-/run/current-system/sw/bin/strata-proxy}" "$port" "$engine"
