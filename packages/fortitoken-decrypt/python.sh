#!/usr/bin/env bash
# a wrapper to point IntelliJ/PyCharm to as a Python env interpreter
set -eEuo pipefail
SCRIPTPATH="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"
REPO="${SCRIPTPATH%/*/*}"

nix run "${REPO}#fortitoken-decrypt.python" -- "$@"
