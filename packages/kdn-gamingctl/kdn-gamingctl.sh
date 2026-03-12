#!/usr/bin/env bash
set -xeEuo pipefail

usage() {
  cat <<EOF
Usage: $0 [options]
  -h               usage

options:
  -f               force changes (skip checks)
  -g               get gaming mode status
  -e               enable gaming mode
  -d               disable gaming mode
EOF
}

is_graphical() {
  if test -n "${is_graphical:-}"; then
    return "$is_graphical"
  fi

  local sc
  sc="$(systemctl --user show -p ActiveState || :)"
  sc="${sc##*=}"
  if test "$sc" = "active"; then
    is_graphical=1
    return 0
  fi
  if ! test -n "${XDG_CURRENT_DESKTOP:-}"; then
    is_graphical=0
    return 1
  fi
}

log() {
  printf "%s: %s\n" "$1" "$2" >&2
}

msg() {
  log "$1" "${2:-}"
  notify-send "kdn-gamingctl: $1" "${2:-}" "${@:3}"
}

err_or_force() {
  local msg="$1" desc="$2"
  if test "$force" = 1; then
    log "$msg" "[forced] $desc"
    return 0
  fi
  msg "$1" "$2"
  return 1
}

main() {
  local force=0 enable=0 disable=0 get=0

  while getopts "hfgde" arg; do
    case "${arg}" in
    g) get=1 ;;
    d) disable=1 ;;
    e) enable=1 ;;
    f) force=1 ;;
    h)
      usage
      exit 0
      ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      echo
      usage
      exit 1
      ;;
    esac
  done

  if test "$enable" = 1; then
    : "${cur:="$(supergfxctl -g)"}"
    if test "$cur" != Integrated; then
      err_or_force "check-current" "can't swtch ''$cur' -> Hybrid (can only switch from Integrated)"
    fi
    supergfxctl -m Hybrid
    if test "$(hostname)" = oams; then
      swaymsg output eDP-1 scale 1.0
    fi
  fi

  if test "$disable" = 1; then
    if test "$cur" != Hybrid; then
      err_or_force "check-current" "can't swtch ''$cur' -> Integrated (can only switch from Hybrid)"
    fi
    supergfxctl -m Integrated
    if test "$(hostname)" = oams; then
      swaymsg output eDP-1 scale 1.25
    fi
  fi
  if test "$get" = 1; then
    if test "$(supergfxctl -g)" = "Hybrid"; then
      echo "active"
      return 0
    else
      echo "inactive"
      return 1
    fi
  fi
}

main "$@" || usage
