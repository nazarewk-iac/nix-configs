#!/usr/bin/env bash
set -xeEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR

# nix run '.#update'

pushd "$(git rev-parse --show-toplevel)"

list_inputs() {
  nix flake metadata --json | jq -r '.locks|.nodes[.root].inputs|keys[]'
}

args=("$@")
update_patches_args=(--update)
updater_args=(--apply)
inputs=()
test "${#args[@]}" -gt 0 || args+=("g:all")
for arg in "${args[@]}" ; do
  case "$arg" in
    g:patches)
      updater_args+=("${update_patches_args[@]}")
      ;;
    g:upstreams)
      mapfile -t -O "${#inputs[@]}" inputs < <(list_inputs | grep -e '-upstream$')
      ;;
    g:all)
      updater_args+=("${update_patches_args[@]}")
      mapfile -t -O "${#inputs[@]}" inputs < <(list_inputs)
      ;;
    i:*)
      inputs+=("${arg#i:}")
      ;;
    *)
      updater_args+=("$arg")
      ;;
  esac
done

mapfile -t inputs < <(printf "%s\n" "${inputs[@]}" | uniq | grep -v '^$' 2>/dev/null || :)

test "${#inputs[@]}" == 0 || nix flake update "${inputs[@]}"

python .flake.patches/update.py "${updater_args[@]}"
