#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

GIT_UTILS_KDN_BASE_DIR="${GIT_UTILS_KDN_BASE_DIR:-"$HOME/dev"}"

# codecommit::eu-north-1://admin@infra-test-zzkl5d-argocd
for entry in "$@"; do
  # strip trailing /
  entry="${entry%/}"

  if [[ "${entry}" != codecommit::*://*@*  ]]; then
    echo "codecommit url must be in format: codecommit::REGION://PROFILE@REPO_NAME" >&2
    exit 1
  fi
  service=codecommit

  profile="${entry##*://}"
  profile="${profile%%@*}"

  region="${entry%%://*}"
  region="${region##*::}"

  org="${profile}/${region}"

  repo="${entry##*@}"

  echo "${GIT_UTILS_KDN_BASE_DIR}/${service}/${org}/${repo}"
done
