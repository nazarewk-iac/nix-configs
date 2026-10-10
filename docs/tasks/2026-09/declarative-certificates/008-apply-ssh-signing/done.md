---
type: Solution
description: kdn-certs apply now signs ssh-user and ssh-host leaves: certinfo parses OpenSSH certificates, the loop branches on the leaf type, and the generated certificate verifies under the declared CA.
timestamp: 2026-10-11T09:30:00+02:00
authored_by: agent
---

# Solution

## What changed

Four files in `packages/kdn-certs`, no new options, no change to `.sops.yaml`, `data/ca/`, or any
host file.

- `internal/certinfo/certinfo.go` — `Read` now recognises an OpenSSH certificate. A file whose first
  token matches `*-cert-v01@openssh.com` goes to a small wire parser instead of `x509.ParseCertificate`.
  The parser recovers `valid_after` (into `Info.NotBefore`) and sets the new `Info.IsSSH` flag.
- `internal/mismatch/mismatch.go` — an SSH certificate carries no issuer common name, so the issuer
  comparison is skipped when `existing.IsSSH` is true. Staleness by `minGenerationDate` still fires.
- `internal/generate/generate.go` — `generateOne` split into `generateTLS` (the old body) and
  `generateSSH`. The SSH branch: decrypts the CA key (the same `<keyfile>.sops` the TLS signer uses),
  generates an ed25519 leaf key, signs with `smallstep.SignSSH`, moves the `ssh-keygen`-style
  `<name>-cert.pub` output to the declared `certFile`, and SOPS-encrypts the leaf key to
  `<keyFile>.sops`. Validity is `+30d` (automation class, design § 7.0). A leaf whose `ca` names a CA
  without `ssh = true` is a hard error.
- `cmd/apply.go` — the loop gets `Deps.SSHSigner`, wired to the same `step` CLI implementation.

## Wire-format facts learned (they cost more than the code)

- The `-cert.pub` blob starts with the **certtype string**, then `nonce`, `key`, `serial`, `type`,
  `key_id`. A parser that skips certtype reads every later field shifted and reports a nonsense
  `cert_type`.
- `principals`, `critical_options`, and `extensions` are **nested length-prefixed blobs**, not inline
  lists. The minimal parser skips each whole blob.
- An SSH ECDSA signature is `string(alg) || string(string(mpint r) || string(mpint s))` — the RFC 3279
  wrapper OpenSSH's `sshkey_ecdsa_sign` uses. It is neither fixed-width `r‖s` nor bare DER.
- `ssh-keygen -V 20300101000000:...` reads the wall-clock in **local time**, not UTC. A fixture that
  "should" hold epoch `1893456000` holds `1893452400` on a CET machine.
- The real `.sops.yaml` rule `hosts/.*/.*\.sops(\.[^.]+)?$` already covers a key file named `id_host`
  (no `.key` infix), so generation into `hosts/...` needs no recipient change.

## Verification

All five acceptance criteria ran in `nix build .#checks.x86_64-linux.kdn-certs-test-ca` (and stay
green in `kdn-certs-test`, which skips the CA-gated cases):

1. `TestGenerateDryRunListsSSHHost` — dry-run reports the `ssh-host` leaf with a reason, writes nothing.
2. `TestGenerateSSHHostAgainstTestCA` — writes `id_host-cert.pub` + `id_host.sops`; the second run
   generates 0 (the existing certificate parses and counts as current).
3. `ssh-keygen -L` output asserted for "host certificate" + principal; the user-certificate path was
   already covered by `TestSignSSHAgainstTestCA`.
4. `verifySSHCertUnderCA` (new, stdlib-only): walks the blob, asserts the embedded `signature_key`
   equals `ssh-keygen -y` on the CA key, and verifies the ECDSA signature over the signed region
   (`cert_parse` in OpenSSH `sshkey.c` defines that region).
5. `certinfo` fixtures (real `ssh-keygen -s` certificates, fixed window): user cert unpadded base64
   and host cert padded, plus truncated-blob and missing-file cases.

The bare `go test ./...` needs no `step` binary: every CA case keeps the `KDN_CERTS_TEST_CA` gate.
