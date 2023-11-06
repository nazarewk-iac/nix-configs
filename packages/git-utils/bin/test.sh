#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

self() {
  if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
    "${BASH_SOURCE[0]%/*}/$1.sh" "${@:2}"
  else
    "$1" "$@"
  fi
}

declare -A dir_tests
dir_tests['https://Organization@dev.azure.com/Organization/Project/_git/Repository']='dev.azure.com/Organization/Project/Repository'
dir_tests['git@ssh.dev.azure.com:v3/Organization/Project/Repository']='dev.azure.com/Organization/Project/Repository'
dir_tests['https://github.com/nazarewk-iac/nix-configs.git']='github.com/nazarewk-iac/nix-configs'
dir_tests['https://gitlab.example.com/GROUP/SUBGROUP/REPO.git']='gitlab.example.com/GROUP/SUBGROUP/REPO'
dir_tests['codecommit::REGION://PROFILE@REPO']='codecommit/PROFILE/REGION/REPO'
dir_tests['https://github.com/nazarewk-iac/nix-configs.git=REL_PATH']='REL_PATH'
dir_tests['https://github.com/nazarewk-iac/nix-configs.git=/ABS_PATH']='/ABS_PATH'

declare -A remote_tests
remote_tests['https://github.com/nazarewk-iac/nix-configs.git=REL_PATH']='https://github.com/nazarewk-iac/nix-configs.git'
remote_tests['https://gitlab.example.com/GROUP/SUBGROUP/REPO.git=/ABS_PATH']="https://gitlab.example.com/GROUP/SUBGROUP/REPO.git"
remote_tests['https://Organization@dev.azure.com/Organization/Project/_git/Repository=REL_PATH']='https://Organization@dev.azure.com/Organization/Project/_git/Repository'

test_g_dir() {
  for i in "${!dir_tests[@]}"; do
    entry="$i"
    expected="${dir_tests[$i]}"
    if [[ "$expected" != /* ]]; then
      expected="$GIT_UTILS_KDN_BASE_DIR/${expected}"
    fi
    got="$(self g-dir "${entry}")"
    if [[ "${got}" != "${expected}" ]]; then
      errors+=("test_g_dir entry ${entry}:
    got      ${got}
    expected ${expected}")
    fi
  done
}

test_g_remote() {
  for i in "${!remote_tests[@]}"; do
    entry="$i"
    expected="${remote_tests[$i]}"
    got="$(self g-remote "${entry}")"
    if [[ "${got}" != "${expected}" ]]; then
      errors+=("test_g_remote entry ${entry}:
    got      ${got}
    expected ${expected}")
    fi
  done
}

main() {
  errors=()
  export SHELLOPTS
  export GIT_UTILS_KDN_BASE_DIR="/tmp/git-utils-test"

  test_g_dir
  test_g_remote

  if [[ "${#errors[@]}" -gt 0 ]]; then
    printf "%s\n\n" "${errors[@]}"
    exit 1
  fi
}

main "$@"
