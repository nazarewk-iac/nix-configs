#!/usr/bin/env bash

main() {
  local result next_token
  local extra=("$@") total=0

  # https://docs.aws.amazon.com/systems-manager/latest/APIReference/API_DescribeParameters.html#API_DescribeParameters_RequestSyntax
  # API MaxResults is value between 1 and 50, so no point giving it more
  start="$SECONDS"
  result="$(time aws ssm describe-parameters --max-items=50 "${extra[@]}" | jq -Mc)"
  while next_token="$(get -er .NextToken)"; do
    count="$(get -r '.Parameters|length')"
    total=$((total + count))
    elapsed=$((SECONDS - start))
    log "PROGRESS: ${total} , $((total / elapsed)) / sec"
    get -r '.Parameters[].Name'
    result="$(time aws ssm describe-parameters --max-items=50 --starting-token="${next_token}" "${extra[@]}" | jq -Mc)"
  done
}

get() {
  jq "$@" <<<"$result"
}

log() {
  echo "$@" >&2
}

main "$@"
