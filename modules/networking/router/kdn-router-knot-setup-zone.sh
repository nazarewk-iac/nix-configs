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

zone_file="$1"
domain="$2"

if test -f "$zone_file"; then
  echo "Zone file $zone_file already exists, skipping..."
  exit 0
fi

knsupdate_args=(--tcp --port "${KNOT_PORT}")
if test -n "${DEBUG:-}"; then
  knsupdate_args+=(--debug)
fi

public_ipv4="$(cat "${PUBLIC_IPV4_PATH}")"
public_ipv6="$(cat "${PUBLIC_IPV6_PATH}")"

update() {
  cat <<EOF | tee >(sed 's/^/knsupdate: /g' >/dev/stderr) | run_knsupdate
server ${KNOT_ADDR}
zone ${domain}
add @             SOA   ns1.${domain} hostmaster.${domain} 1 6h 1h 1w 1h
add @             NS    ns1.${domain}
add ns1.${domain} A     ${public_ipv4}
add ns1.${domain} AAAA  ${public_ipv6}
send
answer
EOF
}

writefile() {
  cat <<EOF | tee >(sed 's/^/zonefile: /g' >&2) >"$zone_file"
${domain}       3600      SOA     ns1.${domain} hostmaster.${domain} 1 6h 1h 1w 1h
${domain}       3600      NS      ns1.${domain}
ns1.${domain}   900       A       ${public_ipv4}
ns1.${domain}   900       AAAA    ${public_ipv6}
EOF
  chmod 0640 "$zone_file"
  chown knot:knot "$zone_file"
  knotc reload
}

writefile