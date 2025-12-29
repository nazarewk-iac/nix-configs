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
  --print-build-logs --show-trace
  # required for `nom` handling, replaces above 2
  #--log-format internal-json -v # TODO: unknown argument --log-format
)
reading_darwin=0
nom_build_args=(
  --no-link
)

cmd="${1}"
: "${name:="${2:-"$(hostname -s)"}"}"
remote=""
flags=""
remote_host=""
shift 2
remote_spec="remote=${name}"
if [[ "${remote_spec:-}" == remote=* ]]; then
  remote="${remote_spec#remote=*}"
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
    # --sudo
  )
elif [[ -n "${1:-}" && "${1}" != -* ]]; then
  name="${1}"
  shift 1
fi

while test "$#" -gt 0; do
  case "$1" in
  --) test "$reading_darwin" = 1 && reading_darwin=0 || reading_darwin=1 ;;
  *) test "$reading_darwin" = 1 && post_args+=("$1") || nom_build_args+=("$1") ;;
  esac
  shift
done

flake_path="$(nix eval --raw '.#self.sourceInfo.outPath')"
post_args+=(--flake "${flake_path}#${name}")
nix copy --to "ssh-ng://${remote_host}" "${flake_path}"

pre_cmd=(ssh -t "$remote_host" "${pre_cmd[@]}")
if test "${DRY_RUN:-0}" == 1; then
  pre_cmd=(echo "${pre_cmd[@]}")
fi

"${pre_cmd[@]}" "sudo nom build '${flake_path}#darwinConfigurations.${name}.system' ${nom_build_args[*]@Q} && sudo darwin-rebuild ${pre_args[*]@Q} ${cmd@Q} ${post_args[*]@Q}"
