#!/usr/bin/env bash
# compares package between local NixOS config, nixpkgs fork and nixpkgs upstream
set -eEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
cd "${BASH_SOURCE[0]%/*}"
info() { echo "[$(date -Iseconds)]" "$@" >&2; }
info STARTING
trap 'info FINISHED' EXIT
test -z "${DEBUG:-}" || set -x

package="${1}"
node="${2:-"$(hostname)"}"
targets=(
  ".#nixosConfigurations.${node}.pkgs.$package"
  "$(jq -r '.nodes.["nixpkgs"].locked | "\(.type):\(.owner)/\(.repo)/\(.rev)"' flake.lock)#${package}"
  "$(jq -r '.nodes.["nixpkgs-upstream"].locked | "\(.type):\(.owner)/\(.repo)/\(.rev)"' flake.lock)#${package}"
)
for target in "${targets[@]}"; do
  printf "%s: " "target=${target@Q}"
  printf "%s\n" "result=$(nix eval "${target}")"
done
