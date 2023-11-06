#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

GIT_UTILS_KDN_BASE_DIR="${GIT_UTILS_KDN_BASE_DIR:-"$HOME/dev"}"

self() {
  "$(self-which "$1")" "${@:2}"
}

self-which() {
  local file="$1"
  if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
    file="${BASH_SOURCE[0]%/*}/$file.sh"
    test -e "${file}" || return 1
  else
    file="$(which "$file")"
  fi
  echo "$file"
}

for entry in "$@"; do
  # strip trailing /
  entry="${entry%/}"

  if [[ "${entry}" == *=* ]]; then
    dir="${entry##*=}"
    if [[ "$dir" != /* ]]; then
      dir="${GIT_UTILS_KDN_BASE_DIR}/$dir"
    fi
    echo "${dir//"//"/"/"}"
    continue
  fi

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

  if svc_bin="$(self-which "g-dir-${service}" 2>/dev/null)"; then
    "${svc_bin}" "${entry}"
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

  dir="${GIT_UTILS_KDN_BASE_DIR}/${service}/${org}/${repo}"
  echo "${dir//"//"/"/"}"
done
