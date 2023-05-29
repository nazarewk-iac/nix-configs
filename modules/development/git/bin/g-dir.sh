#!/usr/bin/env bash
set -eEuo pipefail

shellDir="${shellDir:-"$HOME/dev"}"

bin_suffix=""
if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
  bin_suffix=".sh"
  export PATH="${BASH_SOURCE[0]%/*}:${PATH}"
fi

for entry in "$@"; do
  # strip trailing /
  entry="${entry%/}"

  if [[ "${entry}" == codecommit:* ]]; then
    service=codecommit
  elif [[ "${entry}" == *dev.azure.com* ]]; then
    service=dev.azure.com
  else
    # drop: XXX://
    service="${entry#*://}"
    # drop: git@
    service="${service#*@}"
    # first segment
    service="${service%%/*}"
  fi

  if command -v "g-dir-${service}${bin_suffix}" >/dev/null; then
    "g-dir-${service}${bin_suffix}" "${entry}"
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
