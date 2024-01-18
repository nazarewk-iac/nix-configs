#!/usr/bin/env bash
set -eEuo pipefail

prefix="${BASH_SOURCE[0]%/*/*}"

: "${NM_UI_CADDYFILE_ROOT:="${prefix%/*}/etc/caddy/Caddyfile-root"}"
: "${NM_UI_CADDYFILE:="${prefix%/*}/etc/caddy/Caddyfile"}"
: "${NM_UI_ROOT_DIR:="${prefix%/*}/var/www"}"
: "${NM_UI_AMUI_URL:=https://account.staging.netmaker.io}"
: "${NM_UI_BACKEND_URL:=http://localhost:8081}"
: "${NM_UI_INTERCOM_APP_ID:=}"

vars=(
  NM_UI_CADDYFILE
  NM_UI_CADDYFILE_ROOT
  # used by Caddy
  NM_UI_ROOT_DIR
  NM_UI_AMUI_URL
  NM_UI_NM_BACKEND_URL
  NM_UI_INTERCOM_APP_ID
)

for var in "${vars[@]}"; do
  # shellcheck disable=SC2163
  export "$var"
  echo ">>>> $var set to: '${!var}' <<<<<"
done

pushd "${NM_UI_CADDYFILE%/*}"
caddy run --config="$NM_UI_CADDYFILE_ROOT" "$@"
