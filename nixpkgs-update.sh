#!/usr/bin/env bash
set -xeEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR

# nix run '.#nixpkgs-update"

pushd "$(git rev-parse --show-toplevel)"

if [[ "${update_all:-1}" == 1 ]]; then
  nix flake update
else
  nix flake update nixpkgs-upstream
fi
GITHUB_TOKEN="$(pass show python-keyring/git/github.com/nazarewk)" \
  nix-patcher --update "$@"
nix flake update nixpkgs
