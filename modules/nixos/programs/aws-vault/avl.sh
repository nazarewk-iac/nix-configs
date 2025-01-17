#!/usr/bin/env bash
set -eEuo pipefail

if [ "${#@}" = 0 ]; then
  mapfile -t profiles < <(aws-vault list --profiles)
else
  profiles=("$@")
fi
for p in "${profiles[@]}"; do
  echo "Logging in to $p..." >&2
  # shellcheck disable=SC2016
  if ! aws-vault exec "$p" -- bash -c 'echo "Successfully logged in to $p" >&2'; then
    echo "Failed logging in to $p" >&2
  fi
done
