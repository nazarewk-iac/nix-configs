#!/usr/bin/env bash
set -eEuo pipefail

readarray -t repos <<<"$(gh-repos "$@")"
g-get "${repos[@]}"
