#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

host="$1"
nix run ".#apps.nixinate.${host}"