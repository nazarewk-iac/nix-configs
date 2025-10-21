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
test -z "${DEBUG:-}" || set -x

wd="${BASH_SOURCE[0]%/*}"
out="${wd}/modules/nixos/profile/machine/baseline/ssh_known_hosts"
tmp="${wd}/modules/nixos/profile/machine/baseline/.ssh_known_hosts"

sops decrypt --extract '["networking"]["ssh_hosts"]' "${wd}/default.unattended.sops.yaml" | ssh-keyscan -f - -H -q -v | tee "${tmp}.new"

if test -e "${out}"; then
  difft "${out}" "${tmp}.new"
  mv "${out}" "${tmp}.old"
else
  cat -n "${tmp}.new"
fi
cp "${tmp}.new" "${out}"
