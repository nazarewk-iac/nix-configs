#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

nixos-rebuild boot --use-remote-sudo --print-build-logs --show-trace "$@"