#!/usr/bin/env bash
set -eEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
# shellcheck disable=SC2059
_log() { printf "$(date -Isec) ${1} ${BASH_SOURCE[1]}:${BASH_LINENO[1]}: ${2}\n" "${@:3}" >&2; }
info() { _log INFO "$@"; }
warn() { _log WARN "$@"; }
info STARTING
trap 'info FINISHED' EXIT
test -z "${DEBUG:-}" || set -x

find_packages() {
  if test -d "${1}/nix/packages"; then
    printf "%s" "${1}/nix/packages"
  else
    printf "%s" "${1}/packages"
  fi
}

main() {
  if test $# == 0; then
    cat <<'EOF'
Usage:
  nix run '.#link-python' -- pkg-name
  nix run '.#link-python' -- ALL
EOF
  fi
  : "${repo:="$(git rev-parse --show-toplevel)"}"
  : "${packages:="$(find_packages "${repo}")"}"

  if test "${1:-}" = ALL; then
    mapfile -t links <(grep -l mkPythonScript "${packages}"/*/default.nix | sed 's#.*/\([^/]*\)/.*.nix$#\1#g')
  else
    links=("$@")
  fi

  for name in "${links[@]}"; do
    ln -sfT "$(nom build --no-link --print-out-paths ".#${name}.devEnv")/bin/python" "${packages}/${name}/python"
  done
}

main "$@"
