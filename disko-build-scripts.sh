#!/usr/bin/env bash
set -eEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
cd "${BASH_SOURCE[0]%/*}"
# shellcheck disable=SC2059
info() { printf "[$(date -Iseconds)] ${1}\n" "${@:2}" >&2; }
info STARTING
trap 'info FINISHED' EXIT
test -z "${DEBUG:-}" || set -x

host="${1}"
declare -A scripts

scripts["format"]="formatScript"
scripts["mount"]="mountScript"
scripts["recreate"]="diskoScript"

for key in "${!scripts[@]}" ; do
  nom build -vL ".#nixosConfigurations.${host}.config.system.build.${scripts[${key}]}" -o "disko-${host}-${key}"
done
