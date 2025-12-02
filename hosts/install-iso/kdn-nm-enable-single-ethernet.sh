#!/usr/bin/env bash
set -eEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
cd "${BASH_SOURCE[0]%/*}"
# shellcheck disable=SC2059
info() { printf "[$(date -Iseconds)] ${1}\n" "${@:2}" >&2; }
info STARTING
trap 'info FINISHED' EXIT
test -z "${DEBUG:-}" || set -x

# Function to check if interface is ethernet
is_ethernet() {
  local iface="$1"
  [ -f "/sys/class/net/${iface}/type" ] &&
    [ "$(cat "/sys/class/net/${iface}/type" 2>/dev/null)" = "1" ]
}

# Function to check carrier status
has_carrier() {
  local iface="$1"
  [ -f "/sys/class/net/${iface}/carrier" ] &&
    [ "$(cat "/sys/class/net/${iface}/carrier" 2>/dev/null)" = "1" ]
}

manage_interface() {
  local iface="$1"

  mkdir -p "${config_file%/*}"

  info "managing interface: %s through %s" "${iface}" "${config_file}"

  cat >"${config_file}" <<EOF
# Automatically generated - do not edit manually
# This configuration unmanages all ethernet interfaces except: ${iface}

[device-kdn-ethernet-manage-first]
match-device=interface-name:${iface}
managed=1
EOF
}

main() {
  : "${config_file:="${1:-"/etc/NetworkManager/conf.d/99-manage-first-ethernet.conf"}"}"
  local interfaces=()
  # Find all ethernet interfaces
  for iface in /sys/class/net/*; do
    iface="${iface##*/}"
    if is_ethernet "${iface}"; then
      if has_carrier "${iface}"; then
        # exit on first interface with a carrier
        manage_interface "${iface}"
        exit 0
      fi
      interfaces+=("${iface}")
    fi
  done

  # If no carrier detected, use first available
  if [ ${#interfaces[@]} -gt 0 ]; then
    manage_interface "${interfaces[0]}"
    exit 0
  fi

  info "No ethernet interface found, exiting."
  exit
}

main "$@"
