#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

nix run ".#apps.nixinate.${1}" "${@:2}"