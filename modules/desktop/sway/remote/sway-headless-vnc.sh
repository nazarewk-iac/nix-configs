#!/usr/bin/env bash
set -xeEuo pipefail

usage() {
  cat <<EOF
Usage: $0 [options] [-- [WAYVNC_ARGS...]]

  -h                  usage

Output configuration:
  -n NUMBER           output number, turns into HEADLESS-n, defaults to '1'
  -r WIDTHxHEIGHT     resolution, defaults to '1280x720'
  -p X,Y              position of the output,
                      defaults to 500px off edge of existing outputs
  -w WORKSPACE        workspace to assign to output, defaults to '9'

wayvnc configuration:
  -s                  starts wayvnc server
  -D                  do not disable output after server is stopped
  -H ADDRESS          address to listen on, defaults to '127.0.0.2'
  -P PORT             port to listen on, defaults to '5900'
  -- WAYVNC_ARGS...   arguments to pass down to wayvnc
EOF
}

is_output_missing() {
  swaymsg -rt get_outputs | jq --arg name "$1" -e 'all(.name != $name)'
}

get_detached_x() {
  swaymsg -rt get_outputs | jq 'map(.rect | .x + .width + 500) | max'
}

find_wayland_display() {
  local lock="$(find "${XDG_RUNTIME_DIR}" -maxdepth 1 -name 'wayland-*.lock' | head -n1)"
  local sock="${lock%%.*}}"
  echo -n "${sock##*/}"
}

find_swaysock() {
  find "${XDG_RUNTIME_DIR}" -maxdepth 1 -name 'sway-ipc.*.sock' | head -n1
}

discover_sway() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-"/run/user/$(id -u)"}"
  export SWAYSOCK="${SWAYSOCK:-"$(find_swaysock)"}"
  export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-"$(find_wayland_display)"}"
}

create_output() {
  for ((n=1; n <= output_num; n++)) ; do
    local cur="HEADLESS-${n}"
    if is_output_missing "${cur}"; then
      if [ "${cur}" == "${output}" ]; then
        swaymsg "output ${cur} resolution 1280x720 position $(get_detached_x) 0"
        swaymsg "workspace 9 output ${output}"
      fi
      swaymsg "output ${cur} disable"
      swaymsg create_output
    fi
  done
}

configure_output() {
  if [ -n "${resolution}" ]; then
    swaymsg "output ${output} resolution ${resolution}"
  fi

  if [ -n "${pos}" ]; then
    swaymsg "output ${output} position ${pos%%,*} ${pos##*,}"
  fi

  if [ -n "${workspace}" ]; then
    swaymsg "workspace ${workspace} output ${output}"
  fi
}

cleanup() {
  if [ "${disable}" = 1 ]; then
    swaymsg "output ${output} disable"
  fi
}

main() {
  output_num=1
  host=127.0.0.2
  port=5900
  server=0
  disable=1
  resolution=''
  pos=''
  workspace=''

  while getopts ":n:r:p:w:H:P:shD" arg; do
    case "${arg}" in
      n) output_num="${OPTARG}" ;;
      r) resolution="${OPTARG}" ;;
      p) pos="${OPTARG}" ;;
      w) workspace="${OPTARG}" ;;
      H) host="${OPTARG}" ;;
      P) port="${OPTARG}" ;;
      s) server=1 ;;
      D) disable=0 ;;
      h)
        usage
        exit 0
        ;;
      ?)
        echo "Invalid option: -${OPTARG}."
        echo
        usage
        exit 1
        ;;
    esac
  done

  args=("${@:${OPTIND}}")
  output="HEADLESS-${output_num}"

  discover_sway
  create_output
  configure_output
  swaymsg "output ${output} enable"

  if [ "${server}" = 1 ]; then
    trap cleanup EXIT
    wayvnc --output="${output}" "${args[@]}" "${host}" "${port}"
  fi
}

main "$@"
