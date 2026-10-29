# Public halves of the build-farm clients' Nix store signing keys.
#
# A client signs the store paths it builds locally, so a builder that keeps `require-sigs` on
# (brys, anji, briv) can accept those paths as build inputs instead of rejecting them with
# "lacks a signature by a trusted key". Every host trusts this list: public keys are not secret,
# and trusting a client only means its signed paths are accepted.
#
# The secret half of each key lives in default.unattended.sops.yaml under nix/signing/<name>, and
# only the owning client host installs it (see hosts/oams/default.nix and kdn.build-farm).
[
  "oams-1:seG+Wvb90ebAujmCRcUVCY1KHlQZHJ3MLupr/ThdF8Q="
]
