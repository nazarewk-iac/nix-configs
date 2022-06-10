#!/usr/bin/env bash
# This scripts sets up (and/or re-encrypts) the Password Store dir by doing following
# for each GPG public key in "${PASSWORD_STORE_DIR}/.pubkeys":
#   1. import the keys
#   2. trusts the keys
#   3. parses out and stores all encryption-capable subkeys of identities
#
# Step 3: solves an issue where identity has many different Encryption keys and GPG selects only one of those by default
# see https://github.com/gpg/gnupg/blob/master/doc/DETAILS for `gpg --{show,list}-keys --with-colons` format docs

set -eEuo pipefail

cd "${BASH_SOURCE[0]%/*}"

PREFIX="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
GPG_ID="${PREFIX}/.gpg-id"
PUBKEYS="${PREFIX}/.pubkeys"

get_identity_fingerprint() {
  # returns a GPG fingerprint for the file without importing it
  local filename="$1"
  gpg --show-keys --with-colons "${filename}" | awk -F ':' '$1 == "fpr" {print $10; exit}'
}

get_all_encryption_key_ids() {
  # returns all KEY_IDs having an Encryption capabilities for the identity
  # prefixes them with 0x to be unambiguous
  # suffixes them with ! to force GPG to use that specific subkey instead of a single default for the identity
  local identity="$1"
  # $2 describes key's validity, some relevant examples are:
  # - `d` disabled
  # - `e` expired
  # - `n` not valid
  # - `m` `f` `u` marginally/fully/ultimately valid
  gpg --list-keys --with-colons "${identity}" | awk -F ':' '$1 == "sub" && $2 ~ /[mfu]/ && $12 == "e" {print "0x" $5 "!"}'
}

main() {
  :>"${GPG_ID}.new"

  for filename in "${PUBKEYS}"/*; do
    key_fingerprint="$(get_identity_fingerprint "${filename}")"
    gpg --import "${filename}"
    gpg --import-ownertrust <<<"${key_fingerprint}:6:"
    get_all_encryption_key_ids "${key_fingerprint}" >>"${GPG_ID}.new"
  done

  mv "${GPG_ID}.new" "${GPG_ID}"
  # read a file to arguments array delimited by newlines
  mapfile -t gpg_ids <"${GPG_ID}"
  # reencrypt passwords with keys from .gpg-id file
  pass init "${gpg_ids[@]}"
}

main "$@"
