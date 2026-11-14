#!/usr/bin/env bash
# Report rosec-sops store conflicts to the user, once per new conflict.
#
# ## Why this exists
#
# The `rosec-sops` provider resolves a conflict by "latest `modified` wins". It never loses the
# losing value: it archives every other copy of the item id as
# `.superseded-<id>.<nanos>-<host>.sops.yaml`, a dotfile that no longer resolves as an item. A
# marker file under `.conflicts/` was added later in the fork. Both are silent, so a conflict stays
# unnoticed until the archived value is deleted with the item.
#
# This script turns that silence into one desktop notification per new conflict, plus a persistent
# state file that outlives the notification.
#
# ## Idempotency and no spam
#
# The state file (`~/.local/state/rosec/conflicts.json`) holds one record per conflict, keyed by
# the conflict file's path. A record is written on first sight. A path already in the file gets no
# second notification, however many times this script runs. A record is dropped when its file no
# longer exists, so a resolved conflict stops being reported and a re-appearing path notifies again.
#
# ## Usage
#
#   rosec-conflicts            detect, notify, record
#   rosec-conflicts --list     print the current conflicts, one per line
#   rosec-conflicts --dry-run  detect and print, but write no state and send no notification
#
# Exit codes: `0` always, unless the store path is absent (`2`). A unit that runs this script must
# not fail because a synced directory is offline.
set -euo pipefail

store=""
state_file=""
notify_command=""
mode=check

usage() {
  cat <<'EOF'
Usage: rosec-conflicts [OPTION]...

Detect conflicts in the rosec-sops store and notify once per new conflict.

Options:
  --store PATH       Store root. Required unless ROSEC_CONFLICTS_STORE is set.
  --state PATH       State file. Default: $XDG_STATE_HOME/rosec/conflicts.json
  --notify CMD       Desktop notification command. Default: notify-send
  --list             Print one conflict path per line and exit.
  --dry-run          Print what would be reported; write no state, send no notification.
  -h, --help         Show this help.

Environment:
  ROSEC_CONFLICTS_STORE   The store root, when --store is absent.
  ROSEC_CONFLICTS_STATE   The state file, when --state is absent.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --store)
      store="${2:?--store needs a path}"
      shift 2
      ;;
    --store=*)
      store="${1#--store=}"
      shift
      ;;
    --state)
      state_file="${2:?--state needs a path}"
      shift 2
      ;;
    --state=*)
      state_file="${1#--state=}"
      shift
      ;;
    --notify)
      notify_command="${2:?--notify needs a command}"
      shift 2
      ;;
    --notify=*)
      notify_command="${1#--notify=}"
      shift
      ;;
    --list)
      mode=list
      shift
      ;;
    --dry-run)
      mode=dry-run
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "rosec-conflicts: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

store="${store:-${ROSEC_CONFLICTS_STORE:-}}"
if [ -z "$store" ]; then
  echo "rosec-conflicts: no store. Pass --store or set ROSEC_CONFLICTS_STORE." >&2
  exit 1
fi

# A `~/` prefix arrives from the Nix option unchanged; expand it here so the script works from a
# systemd unit (no shell to expand it) and from a terminal. The comparison quotes the tilde on
# purpose: this is a literal string test, not a path that the shell should expand.
expand_tilde() {
  case "$1" in
    \~/*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    \~) printf '%s' "$HOME" ;;
    *) printf '%s' "$1" ;;
  esac
}

store="$(expand_tilde "$store")"

state_file="${state_file:-${ROSEC_CONFLICTS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/rosec/conflicts.json}}"
state_file="$(expand_tilde "$state_file")"

# No store means nothing to report, and that is not an error: Nextcloud may not have synced the
# directory yet. Record no conflict and stay quiet.
if [ ! -d "$store" ]; then
  echo "rosec-conflicts: store is absent, nothing to check: $store" >&2
  exit 0
fi

# The two shapes a conflict takes in the fork. Both are dotfiles or dot-directories, so a plain
# item listing never shows them:
#
#   1. an archived, superseded copy: `.superseded-<id>.<nanos>-<host>.sops.yaml`
#   2. a marker file under the collection's `.conflicts/` directory, added later in the fork
#
# A Syncthing conflict copy (`*.sync-conflict-*`) is *not* reported here: the provider still
# resolves it on read, and a read never files it. It becomes a superseded archive on the next write.
collect() {
  find "$store" -type f \( \
    -name '.superseded-*.sops.yaml' \
    -o -path '*/.conflicts/*.md' \
    \) -print 2>/dev/null | LC_ALL=C sort
}

conflicts="$(collect || true)"

if [ "$mode" = list ]; then
  if [ -n "$conflicts" ]; then
    printf '%s\n' "$conflicts"
  fi
  exit 0
fi

# The new set, and the set the state file already holds. `comm` needs both inputs sorted, and the
# `LC_ALL=C` sort matches the one in `collect`.
mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
known=""
if [ -f "$state_file" ]; then
  known="$(python3 - "$state_file" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, ValueError):
    data = {}
    path = sys.argv[1]
    if path.endswith("conflicts.json"):
        # Nothing usable. Treat every conflict as new, so a corrupt state file cannot hide one.
        print("", end="")
for record in data.get("conflicts", []):
    if isinstance(record, dict) and isinstance(record.get("path"), str):
        print(record["path"])
PY
)"
fi

current_sorted="$(printf '%s\n' "$conflicts" | sed '/^$/d' | LC_ALL=C sort)"
known_sorted="$(printf '%s\n' "$known" | sed '/^$/d' | LC_ALL=C sort)"

new_conflicts="$(LC_ALL=C comm -23 <(printf '%s\n' "$current_sorted") <(printf '%s\n' "$known_sorted") | sed '/^$/d')"

if [ "$mode" = dry-run ]; then
  printf 'store: %s\n' "$store"
  printf 'state: %s\n' "$state_file"
  printf 'current (%s):\n%s\n' "$(printf '%s' "$current_sorted" | sed '/^$/d' | wc -l)" "$current_sorted"
  printf 'new:\n%s\n' "$new_conflicts"
  exit 0
fi

# Write the state file from the current set, whatever happened below. Every current conflict is
# kept with its first-seen time, so the file answers "which conflicts exist, and since when".
python3 - "$state_file" "$store" "$current_sorted" <<'PY'
import datetime, json, os, sys

state_path, store, listing = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(state_path, "r", encoding="utf-8") as handle:
        old = json.load(handle)
except (OSError, ValueError):
    old = {}

old_by_path = {
    record["path"]: record
    for record in old.get("conflicts", [])
    if isinstance(record, dict) and isinstance(record.get("path"), str)
}

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
records = []
for path in listing.splitlines():
    path = path.strip()
    if not path:
        continue
    previous = old_by_path.get(path, {})
    records.append(
        {
            "path": path,
            "store": store,
            "first_seen": previous.get("first_seen", now),
            "last_seen": now,
        }
    )

document = {
    "version": 1,
    "store": store,
    "updated": now,
    "conflicts": records,
}

tmp = state_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(tmp, state_path)
PY

if [ -z "$new_conflicts" ]; then
  exit 0
fi

# One notification per run, and only when a conflict is new. The count names the scope; the body
# names the resolution route. `rosec-sops conflicts list|resolve` is the planned command from
# docs/tasks/2026-11/rosec-conflict-resolution/; until it lands, the archives are plain files.
count="$(printf '%s\n' "$new_conflicts" | sed '/^$/d' | wc -l)"
summary="$(printf '%s\n' "$new_conflicts" | sed '/^$/d' | head -3 | sed 's|^.*/||' | paste -sd ', ' -)"

title="rosec: ${count} secret conflict(s) need review"
body="Loser values kept as .superseded archives. Review: rosec-conflicts --list. Resolve: rosec-sops conflicts list|resolve. Files: ${summary}"

if [ -n "$notify_command" ]; then
  # A missing notifier must not fail the unit: a headless session has none, and the state file is
  # the durable record either way.
  "$notify_command" "$title" "$body" || true
else
  if command -v notify-send >/dev/null 2>&1; then
    notify-send --app-name=rosec --urgency=normal --expire-time=0 "$title" "$body" || true
  fi
  if command -v swaync-client >/dev/null 2>&1; then
    swaync-client -t >/dev/null 2>&1 || true
  fi
fi

printf '%s\n' "$new_conflicts" >&2
