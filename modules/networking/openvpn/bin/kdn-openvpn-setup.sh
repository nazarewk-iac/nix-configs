#!/usr/bin/env bash
set -eEuo pipefail

msg() {
  echo "$@" >&2
}

err() {
  msg "ERROR:" "$@"
  exit 1
}

confirm() {
  msg "$@"
  read -rp "Continue (y/[n])?" choice
  while true; do
    case "${choice:-n}" in
    y | Y) return 0 ;;
    n | N) return 1 ;;
    *) msg "Invalid choice, try again..." ;;
    esac
  done
}

main() {

  in_config_path="$1"
  in_config_name="${in_config_path##*/}"

  name="${2:-}"
  if [ -z "$name"  ]; then
    name="$(xkcdpass --numwords 2 --delimiter=-)"
    confirm "generated name is '${name}'"
  fi

  base_path=/etc/kdn/openvpn
  out_config_name=config.ovpn
  out_path="$base_path/$name"
  out_config_path="$out_path/$out_config_name"

  in_dst="$out_path/$in_config_name"

  [ -f "$out_config_path" ] && confirm "$out_config_path already exists!"
  if [ ! -f "$in_config_path" ] && [ ! -f "$in_dst" ]; then
    err "neither $in_config_path nor $out_config_path exist, there is nothing to do!"
  fi

  if [ ! -e "$out_path" ]; then
    msg "creating $out_path"
    sudo mkdir -p "$out_path"
  fi
  if [ -f "$in_config_path" ]; then
    msg "moving $in_config_path to $in_dst"
    sudo mv "$in_config_path" "$in_dst"
  fi
  if [ "$out_config_name" != "$in_config_name" ]; then
    msg "symlinking $out_config_path to $in_config_name"
    sudo ln -s "$in_config_name" "$out_config_path"
  fi

  msg "preventing non-root users from accessing $out_path"
  sudo chmod -R og= "$out_path"
  sudo chown -R root:root "$out_path"
}

main "$@"
