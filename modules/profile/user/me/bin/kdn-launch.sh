#!/usr/bin/env bash
set -eEuo pipefail

is_running() {
  if pgrep -fa "${1}" -u "$UID" >/dev/null; then
    were_running+=("${1}")
    return 0
  fi
  return 1
}

swaymsg() {
  if [[ "${1}" == -* ]]; then
    command swaymsg "${@}"
  else
    command swaymsg -- "${@}"
  fi
}

launch() {
  local name="${pattern:-"${1}"}"
  if is_running "${name}"; then
    return 0
  fi
  swaymsg exec "${@}"
  started+=("${name}")
  notify-send "${name}" "started"
}

start_all() {
  start_desktop
  start_priv
  start_work
}

start_desktop() {
  launch blueman-applet
  launch flameshot
}

start_priv() {
  swaymsg workspace 2
  launch nextcloud --background
  start_keepass
  start_comms
  launch logseq
  launch firefox
}

start_comms() {
  swaymsg workspace 2
  launch element-desktop
  launch slack
  launch signal-desktop
}

start_keepass() {
  local pattern="KeePass.exe"
  if is_running "${pattern}"; then
    return 0
  fi
  pass KeePass/drag0nius.kdbx | pattern="${pattern}" launch keepass-drag0nius.kdbx
}

start_work() {
  swaymsg workspace 2
  launch rambox
  swaymsg workspace 1
  launch firefox
  launch idea-ultimate
}

skip_empty_lines() {
  # https://stackoverflow.com/a/41541116
  sed '/^[[:blank:]]*$/ d'
}

on_exit() {
  swaymsg workspace "${original_workspace}"
  mapfile -t deduped < <(comm -3 <(printf "%s\n" "${were_running[@]}" | sort -u) <(printf "%s\n" "${started[@]}" | sort -u) | skip_empty_lines | sort)

  if [[ "${#deduped[@]}" -gt 0 ]]; then
    notify-send "Apps already running" "$(printf "%s, " "${deduped[@]}" | sed 's/, $//')"
  fi
}

main() {
  were_running=()
  started=()
  original_workspace="$(swaymsg -t get_workspaces --raw | jq -r 'map(select(.focused))[0].name')"
  trap on_exit EXIT

  entries=("${@}")

  if [[ "$#" == 0 ]]; then
    entries=("priv")
  fi

  for entry in "${entries[@]}"; do
    start_"${entry//"-"/"_"}"
  done
}

main "$@"
