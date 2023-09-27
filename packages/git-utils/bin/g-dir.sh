#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

GIT_UTILS_KDN_BASE_DIR="${GIT_UTILS_KDN_BASE_DIR:-"$HOME/dev"}"

self() {
  if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
    "${BASH_SOURCE[0]%/*}/$1.sh" "${@:2}"
  else
    "$@"
  fi
}

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

  if self "g-dir-${service}" "${entry}" 2>/dev/null; then
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
  #repo="${repo##*/}"

  dir="${GIT_UTILS_KDN_BASE_DIR}/${service}/${org}/${repo}"

  echo "${dir//"//"/"/"}"
done
