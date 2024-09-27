#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

: "${KNOT_ADDR:="127.0.0.1"}"
: "${KNOT_PORT:="53"}"
: "${TSIG_KEY_PATH:="/etc/knot/knot.conf.d/sops-keys.admin.conf"}"
: "${PUBLIC_IPV4_PATH:="/run/configs/networking/ipv4/network/isp/uplink/address/client"}"
: "${PUBLIC_IPV6_PATH:="/run/configs/networking/ipv6/network/isp/prefix/etra/address/gateway"}"

get_tsig() {
  head -n 1 <"$1" | sed 's/^# //g'
}

run_knsupdate() {
  knsupdate "${knsupdate_args[@]}" \
    --tsigfile <(get_tsig "${TSIG_KEY_PATH}")
}

main() {
  knsupdate_args=(--tcp --port "${KNOT_PORT}")
  if test -n "${DEBUG:-}"; then
    knsupdate_args+=(--debug)
  fi
  local host domain type ip ttl
  host="$(kdn-secrets render-string "$1")"
  domain="$(kdn-secrets render-string "$2")"
  type="$3"
  ip="$(kdn-secrets render-string "$4")"
  ttl="${5:-60}"

  cat <<EOF | tee >(sed 's/^/knsupdate: /g' >/dev/stderr) | run_knsupdate
server ${KNOT_ADDR}
zone ${domain}
delete ${host}.${domain} ${type}
add ${host}.${domain} ${ttl} ${type} ${ip}
send
answer
EOF
}

main "$@"
