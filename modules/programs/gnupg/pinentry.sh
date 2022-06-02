#!/usr/bin/env bash
set -eEuo pipefail

if test -z "${PINENTRY_FLAVOR:-}"; then
  case "${XDG_CURRENT_DESKTOP:-""}" in
  "")
    PINENTRY_FLAVOR=curses
    ;;
  *)
    PINENTRY_FLAVOR=qt
    ;;
  esac
fi

case "${PINENTRY_FLAVOR:-}" in
""|none)
  exit 1 # do not ask for passphrase
  ;;
*)
  exec "pinentry-$PINENTRY_FLAVOR" "$@"
  ;;
esac
