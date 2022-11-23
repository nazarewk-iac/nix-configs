#!/usr/bin/env bash
set -eEuo pipefail

function match_extensions() {
  grep -E "\.($(join_by '|' "$@"))$" <<<"${diff}"
}

function join_by {
  local d="${1-}" f="${2-}"
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

function info() {
  echo "$*" >&2
}

function main() {
  since_revision="${1:-}"
  cd "$(git rev-parse --show-toplevel)"

  if test -z "${since_revision}"; then
    since_revision="$(git rev-list --max-parents=0 HEAD)"
    info "formatting all files"
  else
    info "formatting files changed since $since_revision"
  fi

  diff="$(git diff --name-only "$since_revision")"

  if command -v terraform; then
    while read -r dir; do
      terraform fmt "$dir"
    done < <(match_extensions tf tfvars | sed 's#/[^/]*$##g' | sort | uniq)
  else
    echo 'terraform executable is missing, skipping...'
  fi

  if command -v terragrunt; then
    while read -r file; do
      terragrunt hclfmt --terragrunt-hclfmt-file "$file"
    done < <(match_extensions hcl)
  else
    echo 'terragrunt executable is missing, skipping...'
  fi

  jq="$(command -v jq || command -v gojq || true)"
  if test -n "$jq" && command -v sponge >/dev/null; then
    while read -r file; do
      "$jq" -S <"$file" | sponge "$file"
    done < <(match_extensions {hcl,tf,tfvars}.json)
  else
    echo 'jq/gojq or sponge (moreutils) executables are missing, skipping...'
  fi
}

main "$@"
