#!/usr/bin/env bash
set -eEuo pipefail

for entry in "$@"; do
  echo "${entry}"
  #entry="${entry#*github.com/}"
  #org="${entry%/*}"
  #repo="${entry#*/}"
  #echo "${remoteShellPattern}"
done
