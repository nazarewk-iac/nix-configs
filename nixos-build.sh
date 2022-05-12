#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

nixos-rebuild build -L --show-trace