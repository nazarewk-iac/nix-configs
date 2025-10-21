#!/usr/bin/env bash
set -eEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
cd "${BASH_SOURCE[0]%/*}"
# shellcheck disable=SC2059
info() { printf "[$(date -Iseconds)]${1}\n" "${@:2}" >&2; }
info STARTING
trap 'info FINISHED' EXIT
test -z "${DEBUG:-}" || set -x

nom build --print-build-logs --show-trace --no-link --print-out-paths ".#${1}" "${@:2}"