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

clean_system() {
  nix-collect-garbage -d
}

clean_users() {
  local users
  mapfile -t users < <(list_users)
  for user in "${users[@]}"; do
    sudo -u "$user" -- nix-collect-garbage -d
  done
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
    nix-store --gc
    nix-store --repair --verify --check-contents
  fi
}

main() {
  actions=("${@}")
  test "${#actions[@]}" -gt 0 || actions=(leftovers orphaned-users users system)

  for action in "${actions[@]}"; do
    clean_"${action}"
  done

  nix-store --repair --verify --check-contents
}

main "$@"
