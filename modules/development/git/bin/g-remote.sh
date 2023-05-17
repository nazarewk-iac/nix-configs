#!/usr/bin/env bash
set -eEuo pipefail

for entry in "$@"; do
  # strip trailing /
  entry="${entry%/}"

  echo "${entry}"
  #entry="${entry#*github.com/}"
  #org="${entry%/*}"
  #repo="${entry#*/}"
  #echo "${remoteShellPattern}"
done
