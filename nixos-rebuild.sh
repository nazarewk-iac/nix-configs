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

# One deploy at a time, per target.
#
# `nixos-rebuild` activates through one fixed transient unit on the target,
# `nixos-rebuild-switch-to-configuration`. A second activation that overlaps the first is refused
# with "Unit ... was already loaded or has a fragment file", which `nixos-rebuild` reports as
# "did you forget to use --ask-elevate-password?" -- a message about a collision, not about a
# password. Two ways to collide: a second deploy starts before the first one finished, or the
# client dies (closed terminal, killed tool call) while the target keeps activating. The lock
# covers the first, the wait covers the second.
remote_activation_state() {
  ssh "${remote_host}" systemctl is-active nixos-rebuild-switch-to-configuration.service 2>/dev/null || true
}

if test "${DRY_RUN:-0}" != 1; then
  lock_file="${XDG_RUNTIME_DIR:-/tmp}/nixos-rebuild-${name}.lock"
  exec 9>"${lock_file}"
  if ! flock -n 9; then
    warn "another nixos-rebuild for %s is running (holds %s), wait for it to finish" "${name}" "${lock_file}"
    exit 1
  fi
  case "$cmd" in
  switch | boot | test)
    if test -n "${remote_host}"; then
      waited=0
      while [[ "$(remote_activation_state)" =~ ^(active|activating|reloading|deactivating)$ ]]; do
        test "${waited}" != 0 || warn "an activation is still running on %s, waiting up to %ss" "${remote_host}" 600
        if test "${waited}" -ge 600; then
          warn "the activation on %s did not finish within %ss" "${remote_host}" 600
          exit 1
        fi
        sleep 10
        waited="$((waited + 10))"
      done
    fi
    ;;
  esac
fi

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
