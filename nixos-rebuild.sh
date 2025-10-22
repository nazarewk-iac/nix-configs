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

pre_cmd=(
)
pre_args=(
)
post_args=(
  # below 2 do not work with `--fast` flag due to carrying over to raw `nix` commands
  #--print-build-logs --show-trace
  # required for `nom` handling, replaces above 2
  --log-format internal-json -v
)

name="$(hostname -s)"
cmd="${1}"
remote=""
flags=""
remote_host=""
shift 1

if [[ "${1:-}" == remote=* ]]; then
  remote="${1#remote=*}"
  shift 1
  if [[ "${remote}" == *+* ]]; then
    flags="${remote##*+}"
    remote="${remote%+*}"
  fi
fi

if test -n "${remote:-}"; then
  # remote="etra=kdn@kdn.im@etra.netbird.cloud"
  # remote="kdn.im@etra.netbird.cloud"
  # remote="etra.netbird.cloud"
  # remote="kdn@etra"
  # remote="etra"

  if [[ "${remote}" == *=* ]]; then
    name="${remote%=*}"
    remote="${remote#*=}"
  else
    name="${remote}"
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
    remote_host="${user}@${addr}"
  else
    remote_host="${addr}"
  fi

  pre_args+=(
    --sudo
  )
elif [[ -n "${1:-}" && "${1}" != -* ]]; then
  name="${1}"
  shift 1
fi

if test -n "${remote_host}"; then
  pre_args+=(--target-host "${remote_host}")

  if [[ "${flags}" = *b* ]] || test "$(uname -m)" != "$(ssh "${remote_host}" uname -m)"; then
    pre_args+=(--build-host "${remote_host}")
  fi
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

if test "${DRY_RUN:-0}" == 1; then
  pre_cmd=(echo "${pre_cmd[@]}")
fi

defaults=1
keep_going=1
while test "$#" -gt 0; do
  case "$1" in
  -D | --no-defaults) defaults=0 ;;
  --no-keep-going) keep_going=0 ;;
  *) post_args+=("$1") ;;
  esac
  shift
done

if test "${keep_going}" = 1; then
  post_args+=(--keep-going)
fi

if test "${defaults}" = 1; then
  procs="$(nproc)"
  jobs="$((procs / 10 - 1))"
  jobs="$((jobs > 0 ? jobs : 1))"
  procs="$((procs / jobs - 1))"
  cores="$((procs > 0 ? procs : 1))"
  post_args=(
    --max-jobs="${jobs}"
    --cores="${cores}"
    "${post_args[@]}"
  )
fi

"${pre_cmd[@]}" nixos-rebuild "${pre_args[@]}" "${cmd}" "${post_args[@]}" |& nom --json
