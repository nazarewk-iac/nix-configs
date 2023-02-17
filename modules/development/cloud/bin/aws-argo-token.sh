#!/usr/bin/env bash
set -eEuo pipefail

main() {
  local cluster="$3"
  export AWS_PROFILE="$1"
  export AWS_REGION="$2"
  aws eks get-token --cluster-id="${cluster}" | jq -r '"Bearer \(.status.token)"'
}

log() {
  echo "$@" >&2
}

main "$@"
