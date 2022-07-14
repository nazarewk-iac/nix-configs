#!/usr/bin/env bash
set -eEuo pipefail

if [[ "${1}" = */* ]] ; then
  layout_id="${1%/*}"
  revision="${1#*/}"
else
  layout_id="${1}"
  revision=latest
fi

output_dir="${2:-"."}"

file="$(mktemp -t oryx-src.XXXX.zip)"
trap 'rm $file || :' EXIT
curl -L "https://oryx.zsa.io/${layout_id}/${revision}/source" -o "${file}"
unzip -d "${output_dir}" "${file}"
