#!/usr/bin/env bash

main() {
  export cluster_name="$1"
  export AWS_PROFILE="${2:-"$AWS_PROFILE"}"
  alias="${3:-"$cluster_name"}"

  set -x
  aws eks update-kubeconfig --profile="$AWS_PROFILE" --name="$cluster_name" --alias="$alias"

  cluster_arn="$(kubectl config view --minify | yq -r '.clusters[].name')"
  user="$(kubectl config view --minify | yq -r '.users[].name')"

  kubectl config set-context "$cluster_arn" --cluster="$cluster_arn" --user="$user"

  readarray -t args < <(jq -rn 'env | to_entries[] | select(.key | startswith("AWS_")) | "--exec-env=\(.key)=\(.value)"')
  args+=(
    # see https://stackoverflow.com/a/71319893
    # replaces v1alpha1 -> v1beta1 in:
    # 1) kubectl
    # 2) aws eks get-token result
    --exec-api-version=client.authentication.k8s.io/v1beta1
    --exec-command=bash
    --exec-arg=-c
    --exec-arg="$(
      kubectl config view --minify --flatten -o json | jq -r '.users[].user.exec | [.command] + .args | join(" ") | "\(.) | sed s/v1alpha1/v1beta1/g"'
    )"
  )
  # jq -c '.apiVersion |= "client.authentication.k8s.io/v1beta1"'
  kubectl config set-credentials "$user" "${args[@]}"
}

main "$@"
