#!/usr/bin/env bash
set -eEuo pipefail

script_dir="${BASH_SOURCE[0]%/*}"

: "${CADDYFILE:="${script_dir%/*}/etc/caddy/Caddyfile"}"
: "${ROOT_DIR:="${script_dir%/*}/var/www"}"
: "${AMUI_URL:=https://account.staging.netmaker.io}"
: "${BACKEND_URL:=http://localhost:8081}"
: "${INTERCOM_APP_ID:=}"

for var in CADDYFILE ROOT_DIR AMUI_URL BACKEND_URL INTERCOM_APP_ID; do
  # shellcheck disable=SC2163
  export "$var"
  echo ">>>> $var set to: '${!var}' <<<<<"
done

caddy run --config="$CADDYFILE" "$@"
