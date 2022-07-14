#!/usr/bin/env bash
set -eEuo pipefail

if [[ "${1}" = */* ]] ; then
  layout_id="${1%/*}"
  revision="${1#*/}"
else
  layout_id="${1}"
  revision=latest
fi

file="$(mktemp -t /tmp/oryx-flash.XXXX.bin)"
trap 'rm $file || :' EXIT
curl -L "https://oryx.zsa.io/${layout_id}/${revision}/binary" -o "${file}"
wally-cli "${file}"
