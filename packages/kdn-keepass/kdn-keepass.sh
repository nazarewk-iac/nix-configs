#!/usr/bin/env bash
set -eEuo pipefail

pass_path="KeePass"
: "${KEEPASS_PATH:=""}"
mapfile -t search_dirs <<<"${KEEPASS_PATH//:/$'\n'}"

find_db() {
  local dbname="$1"
  for dir in "${search_dirs[@]}"; do
    local candidate="$dir/$dbname"
    test -e "$candidate" || continue
    echo -n "$candidate"
    return
  done
  echo "error: database $dbname not found in '${KEEPASS_PATH}'!" >&2
  return 1
}

dbname="$1"
pass "$pass_path/$dbname" | keepassxc --pw-stdin "$(find_db "$dbname")"
