#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit # Inherit the errexit option status in subshells.
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
test -z "${DEBUG:=""}" || set -x

tempdir="$(mktemp -d /tmp/podman-nix-run.XXXXXX)"
trap 'rm -rf "$tempdir" || :' EXIT

: "${image:="docker.io/nixos/nix:2.24.9"}"

mkentrypoint() {
  script='
  set -xeEuo pipefail
  ln -s /etc/nix/netrc ~/.netrc
  exec "$0" "$@"
' jq -nc '["/root/.nix-profile/bin/bash","-c", env.script]'
}

mknixconfig() {
  cat <<EOF
experimental-features = nix-command flakes
netrc-file = /etc/nix/netrc

!include /etc/nix/nix.sensitive.conf
EOF
}

main() {
  mkdir -p "$tempdir"
  chmod 0700 "$tempdir"
  cat /etc/nix/netrc >"${tempdir}/netrc"
  cat /etc/nix/nix.sensitive.conf >"${tempdir}/nix.sensitive.conf"
  chmod go-rwx "$tempdir"

  setup_args=(
    --volume="$PWD:$PWD" --workdir "$PWD"
    --volume="${tempdir}/netrc:/etc/nix/netrc:ro"
    --volume="${tempdir}/nix.sensitive.conf:/etc/nix/nix.sensitive.conf:ro"
    --env=NIX_CONFIG="$(mknixconfig)"
    --entrypoint="$(mkentrypoint)"
  )
  podman run --rm -it "${setup_args[@]}" "${image}" "$@"
}

main "$@"

