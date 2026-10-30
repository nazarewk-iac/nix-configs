#!/usr/bin/env bash
# Sign every locally-built store path that has no signature yet.
#
# WHY
# A builder that keeps `require-sigs` on (brys, anji, briv) rejects an unsigned path with
# "lacks a signature by a trusted key". A path the local daemon builds is signed automatically
# through `nix.settings.secret-key-files`. A path that was built BEFORE the key existed, or that a
# different user or daemon registered, stays unsigned and then blocks a remote build or a
# `nix copy` to a builder.
#
# WHAT IT DOES
# Reads the local Nix database, takes every valid path that has a deriver (so it was built here,
# not substituted) and no signature, and signs it with the local signing key.
#
# RUN
#   sudo hack/sign-local-store-paths.sh
#
# It is safe to run repeatedly: paths that already carry a signature are skipped.
set -euo pipefail

key="${KDN_NIX_SIGNING_KEY:-/run/configs/nix/signing/oams-1}"
db=/nix/var/nix/db/db.sqlite

[ "$(id -u)" = 0 ] || {
  echo "run with sudo" >&2
  exit 1
}
[ -r "$key" ] || {
  echo "signing key not readable: $key" >&2
  exit 1
}
command -v sqlite3 >/dev/null || {
  echo "sqlite3 is required" >&2
  exit 1
}

# A path with a deriver was built here. Substituted paths carry the cache's signature, so they are
# already trusted; signing them again is harmless but unnecessary.
mapfile -t paths < <(sqlite3 "$db" \
  "select path from ValidPaths where (sigs is null or sigs = '') and deriver is not null and deriver != '';")

if [ "${#paths[@]}" -eq 0 ]; then
  echo "nothing to sign: every locally-built path already has a signature"
  exit 0
fi

echo "signing ${#paths[@]} unsigned locally-built path(s) with $(basename "$key")"
printf '%s\n' "${paths[@]}" | nix store sign --key-file "$key" --stdin

remaining=$(sqlite3 "$db" \
  "select count(*) from ValidPaths where (sigs is null or sigs = '') and deriver is not null and deriver != '';")
echo "done: $remaining unsigned locally-built path(s) remain"
