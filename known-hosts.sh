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
out="${wd}/modules/universal/profile/machine/baseline/ssh_known_hosts"
tmp="${wd}/modules/universal/profile/machine/baseline/.ssh_known_hosts"

# The ssh_hosts secret is one comma-separated list per host; ssh-keyscan does not split it, so
# expand to one line per alias here (and keep each alias' certificate-covered spelling).
sops decrypt --extract '["networking"]["ssh_hosts"]' "${wd}/default.unattended.sops.yaml" |
  tr ',' '\n' | sed '/^[[:space:]]*$/d' | sort -u |
  ssh-keyscan -f - -H -q -v 2>/dev/null | tee "${tmp}.new"

if test -e "${out}"; then
  difft "${out}" "${tmp}.new"
  mv "${out}" "${tmp}.old"
else
  cat -n "${tmp}.new"
fi
cp "${tmp}.new" "${out}"
