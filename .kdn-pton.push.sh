#!/usr/bin/env bash
set -eEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
cd "${BASH_SOURCE[0]%/*}"
# shellcheck disable=SC2059
_log() { printf "$(date -Isec) ${1} ${BASH_SOURCE[1]}:${BASH_LINENO[1]}: ${2}\n" "${@:3}" >&2; }
info() { _log INFO "$@"; }
warn() { _log WARN "$@"; }
info STARTING
trap 'info FINISHED' EXIT
bash_extra=()
if test "${DEBUG:-}" = 1 ; then set -x; bash_extra+=(-x) ; fi

jj bookmark set -r @- macos-workstation
jj git push --remote kdn-pton
DEBUG=1 ./.kdn-pton.run.sh ./.kdn-pton.on-update.sh

if test "$1" = build ; then
  DEBUG=1 ./.kdn-pton.run.sh nix run '.#darwin-rebuild' -- switch
fi
