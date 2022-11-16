#!/usr/bin/env bash
set -eEuo pipefail

shellDir="${shellDir:-"$HOME/dev"}"

for entry in "$@"; do
  # first segment
  service="${entry%%/*}"
  # drop: XXX://
  service="${service#*://}"
  # drop: git@
  service="${service#*@}"

  # last segment
  repo="${entry##*/}"
  # drop: .git
  repo="${repo%.git}"

  echo "${shellDir}/${service}/${repo}"
done
