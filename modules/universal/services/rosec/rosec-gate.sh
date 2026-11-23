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

# User units do not inherit `DBUS_SESSION_BUS_ADDRESS` from the manager, so derive it: without it
# the desktop notification is skipped and every cue becomes a journal line.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

mkdir -p "$state_dir"

write_state() {
  local state="$1" reason="${2:-}"
  printf 'state=%s\nreason=%s\nupdated=%s\n' \
    "$state" "$reason" "$(date -u +%FT%TZ)" >"$state_file"
}

# True when the provider is unlocked AND the collection holds items.
#
# `org.rosec.Daemon.Status` reports the stored item count even while the provider is locked, and
# the collection `Items` property keeps its paths through a lock, so neither alone means "serving".
# The provider state is truthful for a lock; the item count covers the window right after an unlock,
# where the state already says `unlocked` but the cache is still being populated.
serving() {
  local provider="$1" out count
  # Capture first: `grep -q` closes the pipe on the first match, the writer dies with SIGPIPE
  # (141), and `set -o pipefail` turns that into a failure.
  out="$(rosec status 2>/dev/null || true)"
  grep -qE "^[[:space:]]*${provider}[[:space:]].*[[:space:]]unlocked([[:space:]]|$)" <<<"$out" \
    || return 1
  count="$("${GATE_BUSCTL:-busctl}" "${bus_args[@]}" --json=short call org.freedesktop.secrets \
    /org/freedesktop/secrets/collection/default org.freedesktop.DBus.Properties Get ss \
    org.freedesktop.Secret.Collection Items 2>/dev/null \
    | grep -o '"/org/freedesktop/secrets/collection/[^"]*"' | wc -l)"
  [ "${count:-0}" -gt 0 ]
}

notify() {
  local urgency="$1" summary="$2" body="$3" timeout="$4"
  if [ -n "$notify_bin" ] && [ -x "$notify_bin" ] && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] \
    && "$notify_bin" -u "$urgency" -t "$timeout" -p -r "$replace_id" "$summary" "$body" >/dev/null 2>&1; then
    return 0
  fi
  # No session bus, no notification daemon, or a failed send: the journal is the headless cue.
  logger -t rosec-gate -- "$summary: $body" || true
}

cmd_wait() {
  local provider="$1" deadline=$((SECONDS + probe_timeout))
  write_state unlocking
  while [ "$SECONDS" -lt "$deadline" ]; do
    if serving "$provider"; then
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
  if ! systemctl "${systemctl_args[@]}" is-active --quiet "secret-service-unlock@${provider}.service"; then
    # The gate is not armed; nothing to stop and nothing to report.
    exit 0
  fi
  if serving "$provider"; then
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
