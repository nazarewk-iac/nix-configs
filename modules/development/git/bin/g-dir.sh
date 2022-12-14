#!/usr/bin/env bash
set -eEuo pipefail

shellDir="${shellDir:-"$HOME/dev"}"

for entry in "$@"; do
  if [[ "${entry}" == codecommit:* ]]; then
    service=codecommit
  else
    # drop: XXX://
    service="${entry#*://}"
    # drop: git@
    service="${service#*@}"
    # first segment
    service="${service%%/*}"
  fi

  if command -v "g-dir-${service}" >/dev/null; then
    "g-dir-${service}" "${entry}"
    continue
  fi

  # drop entry until service definition
  org="${entry##*"${service}/"}"
  # first segment
  org="${org%%/*}"

  # drop: XXX://
  repo="${entry#*://}"
  # drop: .git
  repo="${repo%.git}"

  if [ "${repo}" == "${service}/${org}" ]; then
    org=""
  fi

  # drop entry until service definition
  repo="${repo##*"${service}/${org}/"}"
  # last segment
  repo="${repo##*/}"

  dir="${shellDir}/${service}/${org}/${repo}"

  echo "${dir//"//"/"/"}"
done
