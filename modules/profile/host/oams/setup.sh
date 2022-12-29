#!/usr/bin/env bash
set -xeEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

target=/mnt
export APPLY=1

until ./mount.sh "${target}"; do read -p "mount failed, retrying after pressing enter."; done

nixos-install --no-root-password --show-trace --root "${target}" --flake "/home/nazarewk/dev/github.com/nazarewk-iac/nix-configs#oams"

nixos-enter --root "${target}"
until ./umount.sh; do read -p "umount failed, retrying after pressing enter."; done
