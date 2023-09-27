#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

LIMIT="${LIMIT:-999}"
for owner in "$@"; do
  gh repo list "$owner" -L "$LIMIT" --json url | jq -r 'map(.url) | sort[]'
done
