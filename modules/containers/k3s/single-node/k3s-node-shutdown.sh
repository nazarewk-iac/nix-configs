#!/usr/bin/env bash
set -xeEuo pipefail

info() {
  echo "$@" >&2
}

repeat(){
  local times=0 limit="$1"

  until "${@:2}" ; do
    test "${times}" -lt "${limit}" || return 1
    echo "Drain[${times}] failed:" "${@:2}"
    times++
  done
}

drain_initial() {
  kubectl drain "${args[@]}" "${nodes[@]}" "$@"
}

drain_full() {
  kubectl drain "${args[@]}" --disable-eviction "${nodes[@]}"
}

main() {
  nodes=("$@")
  args=(
    --timeout="${INTERVAL:-"60s"}"
    --ignore-daemonsets
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
