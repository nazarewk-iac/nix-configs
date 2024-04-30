#!/usr/bin/env bash
set -eEuo pipefail

: "${expect_script:="${BASH_SOURCE[0]%/*}/kdn-keepass.exp"}"
: "${keepass_pass_path:="KeePass"}"
: "${KEEPASS_PATH:=""}"
mapfile -t search_dirs <<<"${KEEPASS_PATH//:/$'\n'}"

dbname="$1"
dbpath="$(find "${search_dirs[@]}" -maxdepth 1 -name "$dbname" -print -quit)"
if test -z "$dbpath"; then
  echo "error: database $dbname not found in '${KEEPASS_PATH}'!" >&2
  exit 1
fi
expect "${expect_script}" "$dbpath" "$keepass_pass_path/$dbname"
