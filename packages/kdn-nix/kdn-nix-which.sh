#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

help() {
  cat <<EOF >&2
  Usage: "$0" <binary> [options...]
  Find immediate parents/reverse dependencies: nix-which <binary> --referrers
  Find the root using paths: nix-which <binary> --roots
EOF
}
type_immediate() {
  command -v "$1" || command -pv "$1"
}
type_resolved() {
  realpath "$(type_immediate "$1")"
}
type="resolved"
args=()

while test "$#" -gt 0; do
  case "$1" in
  -h | --help) help && exit 0 ;;
  -i | --immediate) type="immediate" ;;
  -r | --resolved) type="resolved" ;;
  *) args+=("$1") ;;
  esac
  shift
done

name="${args[0]}"
args=("${args[@]:1}")
nix-store --query "${args[@]}" "$(type_"$type" "$name")"
