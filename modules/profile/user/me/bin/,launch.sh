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
  if is_running "${1}"; then
    return 0
  fi
  swaymsg exec "${@}"
  notify-send "${1}" "started"
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
}

start_comms() {
  swaymsg workspace 2
  launch element-desktop
  launch slack
  launch signal-desktop
}

start_keepass() {
  if is_running "KeePass.exe"; then
    return 0
  fi
  local db_path="$HOME/Nextcloud/drag0nius@nc.nazarewk.pw/Dropbox import/Apps/KeeAnywhere/drag0nius.kdbx"
  pass KeePass/drag0nius.kdbx | launch keepass "$db_path" -pw-stdin
}

start_work() {
  swaymsg workspace 2
  launch rambox
  swaymsg workspace 1
  launch firefox
  launch idea-ultimate
}

on_exit() {
  swaymsg workspace "${original_workspace}"
  if [[ "${#were_running[@]}" -gt 0 ]]; then
    notify-send "Apps already running" "$(printf "> %s\n" "${were_running[@]}")"
  fi
}

main() {
  were_running=()
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
