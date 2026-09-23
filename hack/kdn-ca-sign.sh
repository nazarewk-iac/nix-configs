#!/usr/bin/env bash
# Sign one leaf certificate with the KDN CA.
#
# The CA private key needs a YubiKey touch, so this script is manual. Run it from the
# repository root. It writes the public cert to hosts/<host>/certs/zellij.pub and the
# SOPS-encrypted private key to hosts/<host>/certs/zellij.key.sops.
#
#   hack/kdn-ca-sign.sh <host> <cn> <san1,san2,...>
#
# Example:
#   hack/kdn-ca-sign.sh oams oams.priv.nb.net.int.kdn.im oams.priv.nb.net.int.kdn.im
set -euo pipefail

usage() {
  cat <<'EOF'
kdn-ca-sign — sign one zellij leaf certificate with the KDN CA.

Usage:
  hack/kdn-ca-sign.sh <host> <cn> <san1,san2,...>

Arguments:
  host   host directory under hosts/, e.g. oams
  cn     certificate common name, e.g. oams.priv.nb.net.int.kdn.im
  sans   comma-separated subjectAltName list, e.g. oams.priv.nb.net.int.kdn.im

A plain name in `sans` becomes a `DNS:` entry. An entry that already carries a type, such
as `IP:10.0.0.1`, keeps it.

The CA key decrypt prompts for the YubiKey touch.
EOF
}

if [ "$#" -ne 3 ]; then
  usage >&2
  exit 2
fi

host="$1"
cn="$2"
sans="$3"

# openssl wants every subjectAltName entry in `TYPE:value` form. A plain name becomes a DNS
# entry, so the caller passes a plain comma-separated list. An entry that already carries a
# colon keeps its own type, so `IP:10.0.0.1` passes through.
san_ext="$(printf '%s\n' "$sans" | tr ',' '\n' | while IFS= read -r entry; do
  case "$entry" in
    *:*) printf '%s,' "$entry" ;;
    *) printf 'DNS:%s,' "$entry" ;;
  esac
done)"
san_ext="${san_ext%,}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "hosts/$host/certs"

sops decrypt --output-type binary data/ca/ca.key.sops > "$tmp/ca.key"

openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/$host.key"

openssl req -new -key "$tmp/$host.key" -out "$tmp/$host.csr" -sha256 \
  -subj "/CN=$cn" -addext "subjectAltName=$san_ext"

openssl x509 -req -in "$tmp/$host.csr" -CA data/ca/ca.pub -CAkey "$tmp/ca.key" \
  -CAcreateserial -out "hosts/$host/certs/zellij.pub" -days 3650 -sha256 \
  -copy_extensions copy

openssl verify -CAfile data/ca/ca.pub "hosts/$host/certs/zellij.pub"

sops encrypt --output-type binary \
  --filename-override "hosts/$host/certs/zellij.key.sops" \
  --output "hosts/$host/certs/zellij.key.sops" \
  "$tmp/$host.key"
