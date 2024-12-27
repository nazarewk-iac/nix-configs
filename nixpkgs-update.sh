#!/usr/bin/env bash
set -xeEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR

# nix run '.#nixpkgs-update"

pushd "$(git rev-parse --show-toplevel)"

list_inputs() {
  nix flake metadata --json | jq -r '.locks|.nodes[.root].inputs|keys[]'
}

args=("$@")
updater_args=()
inputs=()
test "${#args[@]}" -gt 0 || args+=("g:all")
for arg in "${args[@]}" ; do
  case "$arg" in
    g:patches)
      mapfile -t -O "${#inputs[@]}" inputs < <(list_inputs | grep -e '-patch-[[:digit:]]\+$')
      ;;
    g:upstreams)
      mapfile -t -O "${#inputs[@]}" inputs < <(list_inputs | grep -e '-upstream$')
      ;;
    g:all)
      mapfile -t -O "${#inputs[@]}" inputs < <(list_inputs)
      ;;
    i:*)
      inputs+=("${arg#u:}")
      ;;
    *)
      updater_args+=("$arg")
      ;;
  esac
done

mapfile -t inputs < <(printf "%s\n" "${inputs[@]}" | uniq)

test "${#inputs[@]}" == 0 || nix flake update "${inputs[@]}"

GITHUB_TOKEN="$(pass show python-keyring/git/github.com/nazarewk)" \
  nix-patcher --update "${updater_args[@]}"
nix flake update nixpkgs
