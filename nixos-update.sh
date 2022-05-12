#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

git pull
./nixos-build.sh