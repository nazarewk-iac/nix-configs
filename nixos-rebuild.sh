#!/usr/bin/env bash
set -eEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
cd "${BASH_SOURCE[0]%/*}"
info() { echo "[$(date -Iseconds)]" "$@" >&2; }
info STARTING
trap 'info FINISHED' EXIT
test -z "${DEBUG:-}" || set -x

is_available() {
  local hostname="$1"
  nc -vz -w 1 "${hostname}" 22 >&2
}

discover_hostname() {
  local host="$1" hostname
  for domain in "${check_domains[@]}"; do
    hostname="${host}.${domain}"
    if is_available "${hostname}"; then
      printf "%s" "${hostname}"
      return
    fi
  done
  if is_available "${host}"; then
    printf "%s" "${host}"
    return
  fi
  echo "Failed to discover ${host}." >&2
  return 1
}

check_domains=(
  lan.etra.net.int.kdn.im.
  lan.drek.net.int.kdn.im.
  priv.nb.net.int.kdn.im.
  netbird.cloud.
)

pre_cmd=()
pre_args=()
post_args=(
  --print-build-logs --show-trace
  # required for `nom` handling
  --log-format internal-json -v
)

name="$(hostname -s)"
cmd="${1}"
remote=""
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

  if [[ "${addr}" != *.* ]]; then
    addr="$(discover_hostname "${addr}")"
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
elif [[ -n "${1:-}" && "${1}" != -* ]]; then
  name="${1}"
  shift 1
fi
post_args+=(
  --flake ".#${name}"
)

case "$cmd" in
switch | boot | test)
  if test "${remote}" == ""; then
    pre_cmd=(sudo DEBUG="${DEBUG:-}")
  fi
  ;;
esac

"${pre_cmd[@]}" nixos-rebuild "${pre_args[@]}" "${cmd}" "${post_args[@]}" "${@}" |& nom --json
