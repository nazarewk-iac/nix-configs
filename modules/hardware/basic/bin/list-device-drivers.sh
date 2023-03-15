#!/usr/bin/env bash
set -eEuo pipefail

while read -r file; do
    ls -l "${file}"
done < <(compgen -G "/sys/class/${1:-"*"}/${2:-"*"}/device/driver")
