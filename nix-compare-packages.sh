#!/usr/bin/env bash
# compares package between local NixOS config, nixpkgs fork and nixpkgs upstream
set -eEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
cd "${BASH_SOURCE[0]%/*}"
# shellcheck disable=SC2059
info() { printf "[$(date -Iseconds)] ${1}\n" "${@:2}" >&2; }
info STARTING
trap 'info FINISHED' EXIT
test -z "${DEBUG:-}" || set -x

run() {
  if test -n "${remote}"; then
    ssh "${remote}" "${@@Q}"
  else
    "$@"
  fi
}

find_machine_attr() {
  nix eval "${flake_path_resolved}#self" --apply "let node=\"$node\"; in "'
    self: with self; lib.pipe { inherit nixosConfigurations darwinConfigurations; } [
      (builtins.mapAttrs (t: builtins.mapAttrs (h: _: "${t}.${h}")))
      builtins.attrValues
      lib.attrsets.mergeAttrsList
      (x: x.${node})
    ]' --raw
}

: "${remote:="${1:-"$(hostname)"}"}"
: "${package:="${2}"}"
: "${flake_path:="."}"
node="$(run hostname)"
flake_path_resolved="$(nix eval --raw "${flake_path}#self.sourceInfo.outPath")"

attr="$(find_machine_attr)"
if test -n "${remote}"; then
  nix copy --to "ssh-ng://${remote}" "${flake_path_resolved}"
  info "running on ${remote}"
fi

for package in "${@:2}"; do
  targets=(
    "${flake_path_resolved}#${attr}.pkgs.$package"
    "$(jq -r '.nodes.["nixpkgs"].locked | "\(.type):\(.owner)/\(.repo)/\(.rev)"' flake.lock)#${package}"
    "$(jq -r '.nodes.["nixpkgs-upstream"].locked | "\(.type):\(.owner)/\(.repo)/\(.rev)"' flake.lock)#${package}"
  )

  results=()

  for target in "${targets[@]}"; do
    result="$(run nix eval --raw "${target}")"
    results+=("result=${result@Q} for target=${target@Q}")
  done

  printf "%s\n" "${results[@]}"
done
