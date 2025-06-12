#!/usr/bin/env bash
set -xeEuo pipefail

usage() {
  cat <<EOF
Usage: $0 [options] [-- [WAYVNC_ARGS...]]

  -h                  usage

Output configuration:
  -o OUTPUT           name of the non-headless output
  -n NUMBER           headless output number, turns into HEADLESS-n, defaults to '1'
  -r WIDTHxHEIGHT     resolution, defaults to '1280x720'
  -p X,Y              position of the output,
                      defaults to 500px off edge of existing outputs
  -w WORKSPACE        workspace to assign to output, defaults to '9'

wayvnc configuration:
  -s                  starts wayvnc server
  -e/-E               enable output at the end of reconfiguration,
                      defaults to true when running on headless output
  -d/-D               disable output after server is stopped,
                      defaults to true when running on headless output
  -H ADDRESS          address to listen on, defaults to '127.0.0.2'
  -P PORT             port to listen on, defaults to '5900'
  -- WAYVNC_ARGS...   arguments to pass down to wayvnc
EOF
}

is_output_present() {
  swaymsg -rt get_outputs | jq --arg name "$1" -e 'any(.name == $name)' >/dev/null
}

get_detached_y() {
  printf "%d" 0
  #swaymsg -rt get_outputs | jq 'map(.rect | .y + .height + (env.detachment_distance | tonumber)) | max'
}

get_detached_x() {
  swaymsg -rt get_outputs | jq 'map(.rect | .x + .width + (env.detachment_distance | tonumber)) | max'
}

find_wayland_display() {
  local lock
  lock="$(find "${XDG_RUNTIME_DIR}" -maxdepth 1 -name 'wayland-*.lock' | head -n1)"
  local sock="${lock%%.*}"
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

initialize_output() {
  for ((n = 1; n <= output_num; n++)); do
    local cur="HEADLESS-${n}"
    if is_output_present "${cur}"; then
      continue
    fi
    swaymsg create_output
    swaymsg "output ${cur} resolution ${initial_resolution} position $(get_detached_x) $(get_detached_y)"
    if [[ "$cur" != "${output}" ]]; then
      swaymsg "output ${output} disable"
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

  if [ "${enable}" = 1 ]; then
    swaymsg "output ${output} enable"
  fi
}

cleanup() {
  if [ "${disable}" = 1 ]; then
    swaymsg "output ${output} disable"
  fi
}

main() {
  output=''
  output_num=1
  host=127.0.0.2
  port=5900
  server=0
  enable=''
  disable=''
  resolution=''
  pos=''
  workspace=''

  export initial_resolution="1280x720"
  export detachment_distance=500

  while getopts ":o:n:r:p:w:H:P:shDdeE" arg; do
    case "${arg}" in
    o) output="${OPTARG}" ;;
    n) output_num="${OPTARG}" ;;
    r) resolution="${OPTARG}" ;;
    p) pos="${OPTARG}" ;;
    w) workspace="${OPTARG}" ;;
    H) host="${OPTARG}" ;;
    P) port="${OPTARG}" ;;
    s) server=1 ;;
    d) disable=1 ;;
    D) disable=0 ;;
    e) enable=1 ;;
    E) enable=0 ;;
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

  discover_sway

  if test -z "${output}"; then
    output="HEADLESS-${output_num}"
    test -n "${disable}" || disable=1
    test -n "${enable}" || enable=1
  fi

  if [[ "${output}" == HEADLESS-* ]]; then
    initialize_output
  fi

  configure_output

  if [ "${server}" = 1 ]; then
    trap cleanup EXIT
    wayvnc --output="${output}" "${args[@]}" "${host}" "${port}"
  fi
}

main "$@"
