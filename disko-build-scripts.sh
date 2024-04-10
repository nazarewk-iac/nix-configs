#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"
info() { echo "[$(date -Iseconds)]" "$@" >&2; }
info STARTING
trap 'info FINISHED' EXIT

nom build -vL ".#nixosConfigurations.${1}.config.system.build.formatScript" -o "disko-${1}-format"
nom build -vL ".#nixosConfigurations.${1}.config.system.build.mountScript" -o "disko-${1}-mount"
nom build -vL ".#nixosConfigurations.${1}.config.system.build.diskoScript" -o "disko-${1}-recreate"