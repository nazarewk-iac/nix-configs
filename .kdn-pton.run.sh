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

: "${dir:="dev/github.com/nazarewk-iac/nix-configs"}"
: "${host:="kristof.nazarewski@pltp-9kmgdm.lan.etra.net.int.kdn.im."}"

# shellcheck disable=SC2145
ssh -t "${host}" /usr/bin/env bash "${bash_extra[@]}" -c "'cd ${dir@Q} && exec ${@@Q}'"
