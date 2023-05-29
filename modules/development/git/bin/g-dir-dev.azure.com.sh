#!/usr/bin/env bash
set -eEuo pipefail

shellDir="${shellDir:-"$HOME/dev"}"

# codecommit::eu-north-1://admin@infra-test-zzkl5d-argocd
for entry in "$@"; do
  # strip trailing /
  entry="${entry%/}"

  # https://ORGANIZATION@dev.azure.com/ORGANIZATION/PROJECT/_git/REPOSITORY
  # git@ssh.dev.azure.com:v3/ORGANIZATION/PROJECT/REPOSITORY
  if [[ "${entry}" != https://*@dev.azure.com/*/*/_git/* && "${entry}" != git@ssh.dev.azure.com:v3/*/*/* ]]; then
    echo "dev.azure.com url must be in format:" >&2
    echo " - https://ORGANIZATION@dev.azure.com/ORGANIZATION/PROJECT/_git/REPOSITORY" >&2
    echo " - git@ssh.dev.azure.com:v3/ORGANIZATION/PROJECT/REPOSITORY" >&2
    echo "got '${entry}' instead"
    exit 1
  fi

  service=dev.azure.com

  stripped="${entry#"git@ssh.dev.azure.com:v3/"}"
  stripped="${stripped#https://*@dev.azure.com/}"

  org="${stripped%%/*}"
  proj="${stripped#"${org}/"}"
  proj="${proj%%/*}"
  repo="${stripped##*/}"

  echo "${shellDir}/${service}/${org}/${proj}/${repo}"
done
