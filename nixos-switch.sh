#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

sudo nixos-rebuild switch --print-build-logs --show-trace "$@"