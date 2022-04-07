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
  kubectl drain "${args[@]}" "${nodes[@]}" "$@"
}

drain_full() {
  kubectl drain "${args[@]}" --disable-eviction "${nodes[@]}" "$@"
}

main() {
  nodes=("$@")
  args=(
    --delete-emptydir-data
    --by-priority
    --ignore-daemonsets
  )

  if test "${#nodes[@]}" = 0 ; then
    nodes=("$(hostname)")
  fi

  if ! drain_initial --timeout="${INITIAL_DRAIN_TIMEOUT:-120}s"; then
    drain_full --timeout="${FULL_DRAIN_TIMEOUT:-120}s"
  fi
}

main "$@"
