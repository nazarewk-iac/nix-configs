#!/usr/bin/env bash
set -eEuo pipefail

: "${expect_script:="${BASH_SOURCE[0]%/*}/kdn-keepass.exp"}"
: "${keepass_pass_path:="KeePass"}"
: "${KEEPASS_PATH:=""}"
# The Secret Service integration is a host choice: rosec owns `org.freedesktop.secrets` after the
# migration, and re-enabling FdoSecrets would make KeePassXC claim the same name again.
: "${FDO_ENABLED:="false"}"

# The unit cannot answer GUI dialogs: an "unlock before search" prompt, an item-access
# confirmation, or a delete confirmation would block the automated login-unlock or a headless
# secret client forever (measured on oams, cold boot 2026-11-14: a SearchItems call arriving while
# the database loads opened the unlock prompt, which ate the console-submitted password and the
# database stayed locked). Enforce the dialog-free shape of the Secret Service integration in the
# user's real ini — keepassxc writes its own runtime state into that file, so the repo cannot own
# the whole file; this owns the keys below only. A GUI toggle is overridden again at the next
# start. `Enabled` follows `FDO_ENABLED` (default `false`): rosec owns the bus after the migration,
# and `Enabled=false` keeps the GUI from reclaiming it.
ini="${XDG_CONFIG_HOME:-"$HOME/.config"}/keepassxc/keepassxc.ini"
upsert_fdo_key() {
  local key="$1" value="$2"
  mkdir -p "${ini%/*}"
  touch "$ini"
  awk -v key="$key" -v value="$value" '
    BEGIN { sec = 0; found = 0; seen = 0 }
    {
      if ($0 ~ /^\[/) {
        if (sec && !found) { print key "=" value; found = 1 }
        sec = ($0 == "[FdoSecrets]")
        if (sec) seen = 1
        print
        next
      }
      if (sec && !found && index($0, key "=") == 1) { print key "=" value; found = 1; next }
      print
    }
    END {
      if (!seen) { print ""; print "[FdoSecrets]"; print key "=" value }
      else if (sec && !found) print key "=" value
    }
  ' "$ini" >"$ini.tmp" && mv "$ini.tmp" "$ini"
}
upsert_fdo_key Enabled "$FDO_ENABLED"
upsert_fdo_key UnlockBeforeSearch false
upsert_fdo_key ConfirmAccessItem false
upsert_fdo_key ConfirmDeleteItem false
upsert_fdo_key ShowNotification false

mapfile -t search_dirs <<<"${KEEPASS_PATH//:/$'\n'}"

dbname="$1"
dbpath="$(find "${search_dirs[@]}" -maxdepth 1 -name "$dbname" -print -quit)"
if test -z "$dbpath"; then
  echo "error: database $dbname not found in '${KEEPASS_PATH}'!" >&2
  exit 1
fi
exec expect "${expect_script}" "$dbpath" "$keepass_pass_path/$dbname"
