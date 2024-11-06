#!/usr/bin/env bash
set -xeEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR

# nix run '.#nixpkgs-update"

pushd "$(git rev-parse --show-toplevel)"
: "${flake:="./nixpkgs-patcher"}"
(
  cd "$flake"
  nix flake update
  GITHUB_TOKEN="$(pass show python-keyring/git/github.com/nazarewk)" \
    nix-patcher --update "$@"
)
nix flake update nixpkgs
