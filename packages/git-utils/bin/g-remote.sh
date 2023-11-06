#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

for entry in "$@"; do
  if [[ "$entry" == *=* ]]; then
    entry="${entry%%=*}"
  fi
  echo "${entry}"
done
