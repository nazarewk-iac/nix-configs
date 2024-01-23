#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

set -x

# note: -u/--use-update-script doesn't work combined with --flake

nix-update --flake --version=branch=develop netmaker
nix-update --flake --version=branch=master netclient
nix-update --flake --version=branch=master netmaker-ui
nix-update --flake netmaker-pro