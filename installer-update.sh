#!/usr/bin/env bash
set -xeEuo pipefail

cfg="/etc/nixos/configuration.nix"
bkp="${cfg}.bkp"
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

[ -e "${bkp}" ] || cmd mv "${cfg}" "${bkp}"
cat <<EOF | to_file "${cfg}"
{ config, pkgs, ... }:

{
  imports = [ ${bkp} ];

  nix.package = pkgs.nixFlakes;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    git
  ];
}
EOF

# not needed anymore in 2022
#cmd nix-channel --add https://nixos.org/channels/nixos-unstable nixos
#cmd nix-channel --update
cmd nixos-rebuild switch