#!/usr/bin/env bash
# Gate for the rosec Secret Service: wait until a provider actually serves items,
# then keep the gate honest while the store is locked.
#
# Two subcommands, both used by the templated units (`%i` is the rosec provider id):
#
#   rosec-gate wait <provider>   poll the daemon until it reports a populated cache
#   rosec-gate probe <provider>  one periodic check; stops the gate when the store locks
#
# The probe never reads a secret. `secret-tool`/`GetSecret` would call `Service.Unlock`,
# spawn a `rosec-prompt` in the daemon's cgroup, and call `touch_activity` (which defeats
# idle auto-lock). `org.rosec.Daemon.Status` is passive: it returns the served item count.
#
# Scope is explicit: `user` (the normal case) or `system` (used by the container test).
# Every external tool comes from PATH; the unit supplies it with absolute store paths.
set -euo pipefail

scope="${GATE_SCOPE:-user}"
state_dir="${GATE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rosec/gate}"
notify_bin="${GATE_NOTIFY_BIN:-}"
probe_timeout="${GATE_PROBE_TIMEOUT:-45}"
replace_id=4100

case "$scope" in
  user) bus_args=(--user); systemctl_args=(--user) ;;
  system) bus_args=(); systemctl_args=() ;;
  *) echo "unknown GATE_SCOPE: $scope" >&2; exit 2 ;;
esac

mkdir -p "$state_dir"

write_state() {
  local state="$1" reason="${2:-}"
  printf 'state=%s\nreason=%s\nupdated=%s\n' \
    "$state" "$reason" "$(date -u +%FT%TZ)" >"$state_file"
}

# Number of items the daemon currently serves; 0 when the call fails.
served_items() {
  local out n
  out="$("${GATE_BUSCTL:-busctl}" "${bus_args[@]}" call org.freedesktop.secrets \
    /org/rosec/Daemon org.rosec.Daemon Status 2>/dev/null || true)"
  n="$(awk '{print $2}' <<<"$out" 2>/dev/null || true)"
  echo "${n:-0}"
}

notify() {
  local urgency="$1" summary="$2" body="$3" timeout="$4"
  if [ -n "$notify_bin" ] && [ -x "$notify_bin" ] && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    "$notify_bin" -u "$urgency" -t "$timeout" -p -r "$replace_id" "$summary" "$body" >/dev/null 2>&1 || true
  else
    logger -t rosec-gate -- "$summary: $body" || true
  fi
}

cmd_wait() {
  local provider="$1" deadline=$((SECONDS + probe_timeout))
  write_state unlocking
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ "$(served_items)" -gt 0 ]; then
      write_state ready
      notify normal "rosec: $provider ready" "The Secret Service serves secrets again." 3000
      exit 0
    fi
    sleep 0.25
  done
  write_state absent "no served items within ${probe_timeout}s"
  notify normal "rosec: $provider locked" \
    "The Secret Service is locked. Check the YubiKey, then restart secret-service-unlock@${provider}.service." 0
  exit 1
}

cmd_probe() {
  local provider="$1" previous
  previous="$(sed -n 's/^state=//p' "$state_file" 2>/dev/null || true)"
  if [ "$(served_items)" -gt 0 ]; then
    write_state ready
    [ "$previous" = ready ] || notify normal "rosec: $provider ready" "The Secret Service serves secrets." 3000
    exit 0
  fi
  # The store locked. Stop the gate, but never touch the clients that depend on it.
  systemctl "${systemctl_args[@]}" stop "secret-service-unlock@${provider}.service" >/dev/null 2>&1 || true
  write_state locked "served item count dropped to 0"
  if [ "$previous" = ready ]; then
    notify normal "rosec: $provider locked" \
      "The Secret Service locked. Restart secret-service-unlock@${provider}.service after the YubiKey is back." 0
  fi
  exit 0
}

main() {
  local cmd="${1:-}" provider="${2:-}"
  if [ -z "$cmd" ] || [ -z "$provider" ]; then
    echo "usage: rosec-gate {wait|probe} <provider>" >&2
    exit 2
  fi
  state_file="$state_dir/$provider.state"
  case "$cmd" in
    wait) cmd_wait "$provider" ;;
    probe) cmd_probe "$provider" ;;
    *) echo "unknown command: $cmd" >&2; exit 2 ;;
  esac
}

main "$@"
