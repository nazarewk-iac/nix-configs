#!/usr/bin/env bash
set -xeEuo pipefail

usage() {
 return
}

is_output_missing() {
  swaymsg -rt get_outputs | jq --arg name "$1" -e 'all(.name != $name)'
}

get_detached_x() {
  swaymsg -rt get_outputs | jq 'map(.rect | .x + .width + 500) | max'
}

main() {
  local output_num=1
  local host=127.0.0.2
  local port=5900
  local server=0
  local resolution=''
  local pos=''
  local workspace=''

  while getopts ":n:r:p:w:H:P:S" arg; do
    case "${arg}" in
      n) output_num="${OPTARG}" ;;
      r) resolution="${OPTARG}" ;;
      p) pos="${OPTARG}" ;;
      w) workspace="${OPTARG}" ;;
      H) host="${OPTARG}" ;;
      P) port="${OPTARG}" ;;
      S) server=1 ;;
      ?)
        echo "Invalid option: -${OPTARG}."
        echo
        usage
        exit 1
        ;;
    esac
  done

  local args=("${@:${OPTIND}}")
  local output="HEADLESS-${output_num}"

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

  if [ -n "${resolution}" ]; then
    swaymsg "output ${output} resolution ${resolution}"
  fi

  if [ -n "${pos}" ]; then
    swaymsg "output ${output} position ${pos%%,*} ${pos##*,}"
  fi

  if [ -n "${workspace}" ]; then
    swaymsg "workspace ${workspace} output ${output}"
  fi
  swaymsg "output ${output} enable"

  if [ "${server}" = 1 ]; then
    exec wayvnc --output="${output}" "${args[@]}" "${host}" "${port}"
  fi
}

main "$@"
