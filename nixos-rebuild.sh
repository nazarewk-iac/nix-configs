#!/usr/bin/env bash
set -eEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
cd "${BASH_SOURCE[0]%/*}"
info() { echo "[$(date -Iseconds)]" "$@" >&2; }
info STARTING
trap 'info FINISHED' EXIT
test -z "${DEBUG:-}" || set -x

pre_args=()
post_args=(
  --print-build-logs --show-trace
  # required for `nom` handling
  --log-format internal-json -v
)

cmd="${1}"
shift 1
if [[ "${1:-}" == remote=* ]]; then
  # remote="etra=kdn@kdn.im@etra.netbird.cloud"
  # remote="kdn.im@etra.netbird.cloud"
  # remote="etra.netbird.cloud"
  # remote="kdn@etra"
  # remote="etra"
  remote="${1#remote=}"
  shift 1
  if [[ "${remote}" == *=* ]]; then
    name="${remote%=*}"
    remote="${remote#*=}"
  fi
  addr="${remote}"
  if [[ "${addr}" == *@* ]]; then
    user="${addr%@*}"
    addr="${addr##*@}"
  fi
  if test -z "${name:-}"; then
    name="${addr%%.*}"
  fi

  if test -n "${user:-}"; then
    pre_args+=(
      --target-host "${user}@${addr}"
    )
  else
    pre_args+=(
      --target-host "${addr}"
    )
  fi

  pre_args+=(
    --use-remote-sudo
  )
  post_args+=(
    --flake ".#${name}"
  )
fi

nixos-rebuild "${pre_args[@]}" "${cmd}" "${post_args[@]}" "${@}" |& nom --json
