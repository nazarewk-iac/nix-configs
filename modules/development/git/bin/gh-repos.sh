#!/usr/bin/env bash
set -eEuo pipefail

LIMIT="${LIMIT:-999}"
for owner in "$@"; do
  gh repo list "$owner" -L "$LIMIT" --json owner,name | jq -r '.[] | "\(.owner.login)/\(.name)"'
done
