#!/usr/bin/env bash
set -eEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
# shellcheck disable=SC2059
_log() { printf "$(date -Isec) ${1} ${BASH_SOURCE[1]}:${BASH_LINENO[1]}: ${2}\n" "${@:3}" >&2; }
info() { _log INFO "$@"; }
warn() { _log WARN "$@"; }
info STARTING
trap 'info FINISHED' EXIT
: "${DEBUG:=0}"
test "${DEBUG}" = 1 || set -x

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

: "${src:="${DEFAULT_SRC:-"${BASH_SOURCE[0]%/*}"}"}"

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
shift 1
: "${name:="${1:-"$(hostname -s)"}"}"
remote=""
remote_host=""
test $# -lt 1 || shift 1
remote_spec="${name}"
if [[ "${remote_spec:-}" == remote=* ]]; then
  remote="${remote_spec#remote=*}"
  if [[ "${remote}" == *+* ]]; then
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

flake_path="$(nix eval --raw "$src#self.sourceInfo.outPath")"
post_args+=(--flake "${flake_path}#${name}")
if test -n "${remote_host}"; then
  nix copy --to "ssh-ng://${remote_host}" "${flake_path}"
  ssh -t "$remote_host" "DEBUG='${DEBUG}' nix run '$flake_path#darwin-rebuild' -- ${cmd@Q} ${name@Q} ${nom_build_args[*]@Q} -- ${post_args[*]@Q}"
else
  pre_cmd=(bash)
  if test "${DRY_RUN:-0}" == 1; then
    pre_cmd=(echo "${pre_cmd[@]}")
  fi
  if test "${DEBUG}" = 1; then
    pre_cmd+=(-x)
  fi
  pre_cmd+=(-c)

  # required for the linux-builder, otherwise throws error about not being on linux and that substitutes are not allowed
  nom_build_args+=(--always-allow-substitutes)

  "${pre_cmd[@]}" "nom build --no-link '${flake_path}#darwinConfigurations.${name}.system' ${nom_build_args[*]@Q} && sudo darwin-rebuild ${pre_args[*]@Q} ${cmd@Q} ${post_args[*]@Q}"
fi
