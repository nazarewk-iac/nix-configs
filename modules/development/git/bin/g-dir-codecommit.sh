#!/usr/bin/env bash
set -eEuo pipefail

shellDir="${shellDir:-"$HOME/dev"}"

# codecommit::eu-north-1://admin@infra-test-zzkl5d-argocd
for entry in "$@"; do
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

  echo "${shellDir}/${service}/${org}/${repo}"
done
