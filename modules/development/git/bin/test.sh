#!/usr/bin/env bash
set -eEuo pipefail

bin_suffix=""
if [[ "${BASH_SOURCE[0]##*/}" == *.sh ]]; then
  bin_suffix=".sh"
  export PATH="${BASH_SOURCE[0]%/*}:${PATH}"
fi

declare -A dir_tests
dir_tests['https://Organization@dev.azure.com/Organization/Project/_git/Repository']="dev.azure.com/Organization/Project/Repository"
dir_tests['git@ssh.dev.azure.com:v3/Organization/Project/Repository']="dev.azure.com/Organization/Project/Repository"
dir_tests['https://github.com/nazarewk-iac/nix-configs.git']="github.com/nazarewk-iac/nix-configs"
dir_tests['codecommit::REGION://PROFILE@REPO']='codecommit/PROFILE/REGION/REPO'

test_g_dir() {
  for i in "${!dir_tests[@]}"; do
    remote="$i"
    expected="$shellDir/${dir_tests[$i]}"
    got="$(g-dir.sh "${remote}")"
    if [[ "${got}" != "${expected}" ]]; then
      errors+=("${remote}:
    got      ${got}
    expected ${expected}")
    fi
  done
}

main() {
  errors=()
  export SHELLOPTS
  export shellDir="/tmp"

  test_g_dir

  for error in "${errors[@]}"; do
    echo "${error}"
  done

  if [[ "${#errors[@]}" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
