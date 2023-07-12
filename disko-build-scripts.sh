#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

nix build -vL ".#nixosConfigurations.${1}.config.system.build.formatScript" -o "disko-${1}-format"
nix build -vL ".#nixosConfigurations.${1}.config.system.build.mountScript" -o "disko-${1}-mount"
nix build -vL ".#nixosConfigurations.${1}.config.system.build.diskoScript" -o "disko-${1}-recreate"