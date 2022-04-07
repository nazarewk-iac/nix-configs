#!/usr/bin/env bash
set -xeEuo pipefail

info() {
  echo "$@" >&2
}

repeat(){
  local times=0 limit="$1"

  while test "${times}" -lt "${limit}" ; do
    if "${@:2}" ; then
      return 0
    fi
    echo "Drain[${times}] failed:" "${@:2}"
    times++
  done
  return 1
}

drain_initial() {
  kubectl drain "${args[@]}" --ignore-daemonsets "${nodes[@]}" "$@"
}

drain_full() {
  kubectl drain "${args[@]}" --ignore-daemonsets --disable-eviction "${nodes[@]}" "$@"
}

main() {
  nodes=("$@")
  args=(
    --timeout="${INTERVAL:-"60s"}"
    --delete-emptydir-data
  )
  if ! repeat "${DRAIN_INITIAL_COUNT:=2}" drain_initial ; then
    repeat "${DRAIN_FULL_COUNT:=10}" drain_full
  fi

  if [[ "${nodes[*]}" == *"$(hostname)"* ]] ; then
    sudo systemctl stop k3s.service
  fi
}

main "$@"
