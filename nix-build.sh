#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

nix build --print-build-logs --show-trace --no-link --print-out-paths ".#${1}" "${@:2}"