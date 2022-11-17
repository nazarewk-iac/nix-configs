#!/usr/bin/env bash
set -eEuo pipefail

shellDir="${shellDir:-"$HOME/dev"}"

for entry in "$@"; do
  # drop: XXX://
  service="${entry#*://}"
  # drop: git@
  service="${service#*@}"
  # first segment
  service="${service%%/*}"

  # last segment
  repo="${entry##*/}"
  # drop: .git
  repo="${repo%.git}"

  echo "${shellDir}/${service}/${repo}"
done
