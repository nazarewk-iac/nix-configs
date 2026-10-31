#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

if [[ $EUID -ne 0 ]]; then
  echo "restarting as root..." >&2
  exec sudo DEBUG="${DEBUG:-}" "$BASH" "$0" "$@"
fi

log() {
  printf "$1: %s\n" "${@:2}"
}

# list_users prints the name of each user with a home directory.
list_users() {
  getent passwd | cut -d: -f1,6 | grep ':/home/' | cut -d: -f1
}

# user_exists tests if a user name has a passwd entry.
user_exists() {
  getent passwd "$1" >/dev/null 2>&1
}

# home_of prints the home directory of a user name.
home_of() {
  getent passwd "$1" | cut -d: -f6
}

# active_home_generation prints the store path of the active home-manager
# generation for one home directory. The file "current-home" holds this path.
# Print an empty string when the file does not exist.
active_home_generation() {
  local home="$1" gcroots="${1}/.local/state/home-manager/gcroots/current-home"
  if [[ -L "${gcroots}" ]]; then
    realpath "${gcroots}" 2>/dev/null || printf ''
    return 0
  fi
  printf ''
}

# handle_leftover_profile removes one profile link. A link matches the name
# "<base>-<number>-link". The system link is active when its sibling "system"
# link points to the same store path. A home-manager link is active when the
# file "current-home" of the same home points to the same store path. The
# script removes every other matching link.
handle_leftover_profile() {
  local link="${1}" target base active active_target home
  [[ "${link##*/}" =~ -[[:digit:]]+-link$ ]] || return 0

  base="${link%-*-link}"
  active="${base}"
  target="$(realpath "${link}" 2>/dev/null || printf '')"

  if [[ "${base##*/}" == "system" ]]; then
    active_target="$(realpath "${base}" 2>/dev/null || printf '')"
  else
    home="$(active_home_parent "${link}")"
    active_target="$(active_home_generation "${home}")"
    # Fall back to the sibling link when no "current-home" exists.
    [[ -n "${active_target}" ]] || active_target="$(realpath "${active}" 2>/dev/null || printf '')"
  fi

  if [[ -n "${target}" && "${target}" == "${active_target}" ]]; then
    log info "[KEEP  ] '${link}' seems active, '${active}' also points to '${target}'"
    ((kept += 1))
  else
    log info "[REMOVE] '${link}' seems inactive, '${active}' points to '${active_target}', not '${target}'"
    rm -f "${link}"
    ((deleted += 1))
  fi
}

# active_home_parent prints the home directory of a profile link. The link
# lives in "<home>/.local/state/nix/profiles/" or in
# "/nix/var/nix/profiles/per-user/<user>/".
active_home_parent() {
  local link="${1}" dir
  dir="$(dirname "${link}")"
  case "${dir}" in
  */.local/state/nix/profiles) printf '%s' "${dir%/.local/state/nix/profiles}" ;;
  /nix/var/nix/profiles/per-user/*) home_of "${dir##*/}" ;;
  *) printf '' ;;
  esac
}

handle_leftover_result() {
  local link="$1"
  [[ "${link##*/}" == result || "${link##*/}" == result-* ]] || return 0
  log info "[REMOVE] '${link}' seems to be a nix build result"
  rm -f "${link}"
  ((deleted += 1))
}

# gc_batch runs ONE bounded deletion step. Returns 1 when the store has no dead
# paths left, 0 after it deleted something. Few dead paths use a byte-bounded
# `nix-store --gc`; many dead paths delete at most MAX_PATHS of them directly.
# Lix 2.95 has no `--max-links`, so the count bound uses a `--delete` slice.
gc_batch() {
  local -a dead
  local before after t0 t1 freed
  mapfile -t dead < <(nix-store --gc --print-dead)
  if [[ ${#dead[@]} -eq 0 ]]; then
    return 1
  fi
  before=$(df --output=avail -B1 /nix/store | tail -n1)
  t0=$(date +%s)
  if [[ ${#dead[@]} -le ${MAX_PATHS} ]]; then
    nix-store --gc --max-freed "${MAX_FREED}"
  else
    nix-store --delete "${dead[@]:0:${MAX_PATHS}}" || true
  fi
  t1=$(date +%s)
  after=$(df --output=avail -B1 /nix/store | tail -n1)
  freed=$(((after - before) / 1048576))
  log info "[GC     ] batch: dead=${#dead[@]} freed=${freed}MiB elapsed=$((t1 - t0))s"
  return 0
}

# gc_until_done repeats bounded batches until the store is clean or a batch frees
# nothing (a safety stop against an infinite loop).
gc_until_done() {
  local before after
  while true; do
    before=$(df --output=avail -B1 /nix/store | tail -n1)
    if ! gc_batch; then
      log info "[GC     ] no dead paths left"
      break
    fi
    after=$(df --output=avail -B1 /nix/store | tail -n1)
    if [[ "${after}" == "${before}" ]]; then
      log warn "[GC     ] batch freed nothing, stopping"
      break
    fi
  done
}

clean_system() {
  nix-env -p /nix/var/nix/profiles/system --delete-generations old
  gc_until_done
}

clean_users() {
  local users
  mapfile -t users < <(list_users)
  for user in "${users[@]}"; do
    sudo -u "$user" -- nix-collect-garbage -d --max-freed "${MAX_FREED}"
  done
  gc_until_done
}

# clean_orphaned_users removes the profiles and the gcroots of each user that
# has no passwd entry. Such a user keeps a live generation that holds store
# paths with no owner.
clean_orphaned_users() {
  local dir owner uid deleted=0
  for dir in /nix/var/nix/profiles/per-user/* /nix/var/nix/gcroots/per-user/*; do
    [[ -e "${dir}" ]] || continue
    owner="${dir##*/}"
    user_exists "${owner}" && continue
    uid="$(stat -c '%u' "${dir}")"
    if getent passwd "${uid}" >/dev/null 2>&1; then
      log warn "[KEEP  ] '${dir}' belongs to uid ${uid} with a passwd entry"
      continue
    fi
    log info "[REMOVE] '${dir}' belongs to an unknown user"
    rm -rf "${dir}"
    ((deleted += 1))
  done
  log info "[SUMMARY] removed ${deleted} orphaned user directories"
}

clean_leftovers() {
  local link deleted=0 kept=0
  mapfile -t gc_roots < <(kdn-nix-list-roots)
  for gc_root in "${gc_roots[@]}"; do
    link="${gc_root%% -> *}"
    handle_leftover_profile "${link}"
    handle_leftover_result "${link}"
  done

  log info "[SUMMARY] kept ${kept} links, deleted ${deleted} links"
  if test "${deleted}" -gt 0; then
    gc_until_done
    if [[ "${VERIFY}" == "1" ]]; then
      nix-store --repair --verify --check-contents
    fi
  fi
}

usage() {
  cat >&2 <<'EOF'
usage: kdn-nix-collect-garbage [OPTIONS] [ACTION...]

Options:
  -c, --batch-count N   max dead paths deleted per batch (default 2000)
  -s, --batch-size SIZE max bytes freed per batch, e.g. 2G, 500M (default 2G)
  -h, --help            show this help

Actions (default: all, in this order):
  leftovers orphaned_users users system

Each store collection runs in bounded batches: a batch stops after deleting
MAX_PATHS dead paths or freeing MAX_FREED bytes, whichever comes first. The loop
repeats until nothing is left, so the GC lock is held one batch at a time.
EOF
}

main() {
  local -a actions=()
  MAX_PATHS="${MAX_PATHS:-2000}"
  MAX_FREED="${MAX_FREED:-2G}"
  VERIFY="${VERIFY:-0}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -c | --batch-count)
      MAX_PATHS="$2"
      shift 2
      ;;
    --batch-count=*)
      MAX_PATHS="${1#*=}"
      shift
      ;;
    -s | --batch-size)
      MAX_FREED="$2"
      shift 2
      ;;
    --batch-size=*)
      MAX_FREED="${1#*=}"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --verify)
      VERIFY=1
      shift
      ;;
    leftovers | orphaned_users | users | system)
      actions+=("$1")
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2
      ;;
    esac
  done
  export MAX_PATHS MAX_FREED VERIFY

  test "${#actions[@]}" -gt 0 || actions=(leftovers orphaned_users users system)
  log info "[CONF   ] batch-count=${MAX_PATHS} batch-size=${MAX_FREED}"

  for action in "${actions[@]}"; do
    clean_"${action}"
  done

  # The full-store verify is slow and holds the store for minutes, so it is opt-in.
  if [[ "${VERIFY}" == "1" ]]; then
    nix-store --repair --verify --check-contents
  fi
}

main "$@"
