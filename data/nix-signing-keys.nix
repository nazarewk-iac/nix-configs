# Public halves of the build-farm clients' Nix store signing keys.
#
# A client signs the store paths it builds locally, so a builder that keeps `require-sigs` on
# (brys, anji, briv) can accept those paths as build inputs instead of rejecting them with
# "lacks a signature by a trusted key". Only the builder hosts trust this list (gated on
# `kdn.nix.remote-builder.enable`), not routers or NAS — trusting a client means accepting any path
# it signs, so a compromised laptop must not escalate across the whole fleet.
#
# The secret half of each key lives in a per-host sops file (`hosts/<host>/*.sops.yaml`, e.g.
# hosts/oams/secrets.sops.yaml), decryptable only by that host and the oams + brys YubiKeys. Only
# the owning client host installs it (see hosts/oams/default.nix and kdn.build-farm).
[
  "oams-1:seG+Wvb90ebAujmCRcUVCY1KHlQZHJ3MLupr/ThdF8Q="
]
