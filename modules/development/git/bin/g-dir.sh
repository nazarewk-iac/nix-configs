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

  # drop entry until service definition
  org="${entry##*"${service}/"}"
  # first segment
  org="${org%%/*}"

  # drop entry until service definition
  repo="${entry##*"${service}/${org}/"}"
  # first segment
  repo="${repo%%/*}"
  # drop: .git
  repo="${repo%.git}"

  echo "${shellDir}/${service}/${org}/${repo}"
done
