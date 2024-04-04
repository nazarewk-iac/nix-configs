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

list_users() {
  getent passwd | cut -d: -f1,6 | grep ':/home/' | cut -d: -f1
}

handle_leftover_profile() {
  local link="${1}" target active active_target
  [[ "${link##*/}" =~ -[[:digit:]]+-link$ ]] || return 0

  active="${link%-*-link}"
  target="$(realpath "${link}")"
  active_target="$(realpath "${active}")"
  if test "${target}" == "${active_target}"; then
    log info "[KEEP  ] '${link}' seems active, '${active}' also points to '${target}'"
    ((kept += 1))
  else
    log info "[REMOVE] '${link}' seems inactive, '${active}' points to '${active_target}', not '${target}'"
    rm "${link}"
    ((deleted += 1))
  fi
}

handle_leftover_result() {
  local link="$1"
  [[ "${link##*/}" == result* ]] || return 0
  log info "[REMOVE] '${link}' seems to be a nix build result"
  rm "${link}"
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
  fi
}

main() {
  actions=("${@}")
  test "${#actions[@]}" -gt 0 || actions=(leftovers users system)

  for action in "${actions[@]}"; do
    clean_"${action}"
  done
}

main "$@"
