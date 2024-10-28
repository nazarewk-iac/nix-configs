#!/usr/bin/env bash
set -xeEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR

cfg="/etc/nixos/configuration.nix"

if [ "${APPLY:-}" = 1 ] ; then
  cmd () { "$@"; }
else
  cmd () { echo "$@"; }
  set +x
fi

to_file() {
  if [ "${APPLY:-}" = 1 ] ; then
    tee "$@"
  else
    tee
  fi
}

[ -e "/etc/nixos/configuration.bkp.nix" ] || cmd mv "${cfg}" "/etc/nixos/configuration.bkp.nix"
curl -L "https://raw.githubusercontent.com/nazarewk-iac/nix-configs/main/configurations/remote-access-installer/default.nix" | to_file "${cfg}"

cmd nixos-rebuild switch
