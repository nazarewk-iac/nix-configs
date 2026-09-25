---
type: Solution
description: The kdn.ssh-ca aspect wires server trust on nixos and darwin, client trust on homeManager, and the kdn-certs ssh login flow signs interactive user certificates.
timestamp: 2026-09-25T21:10:00+02:00
authored_by: agent
---

# Solution

## Root cause analysis

The tree held no SSH certificate layer. `TrustedUserCAKeys`, `HostCertificate`, `@cert-authority`
and `CertificateFile` appeared in no module. The `kdn` CA could sign X.509 leaves only, and the
`kdn-certs` CLI had no SSH sign path.

The design § 7.5 open risk was confirmed by the earlier run: nix-darwin declares
`services.openssh.extraConfig`, not `services.openssh.settings`. The user resolved it as option A on
2026-09-25: the `darwin` class writes the two directives as a `sshd_config` fragment through
`extraConfig`. No local shim is added.

## Solution

`modules/den/aspects/ssh-ca.nix` is the `kdn.ssh-ca` aspect. It has the classes `nixos`, `darwin`
and `homeManager`, and it declares no `enable` option. It includes `kdn.ca-dag` and
`kdn.certificates`, so it carries both option trees.

### Server side

- `nixos` writes `services.openssh.settings.TrustedUserCAKeys` and `.HostCertificate`.
- `darwin` writes both directives as text through `services.openssh.extraConfig`.

The CA public key is derived from the CA X.509 certificate: `openssl x509 -pubkey` then
`ssh-keygen -i -m PKCS8`. The derivation runs for the host platform only, so it needs no foreign
builder. The host certificate is the `certPath` of the first `ssh-host` leaf.

### Client side

The `homeManager` class writes `~/.ssh/config.d/50-kdn-ssh-ca.config` with `CertificateFile` and a
`UserKnownHostsFile` line, plus a managed `known_hosts` fragment that holds the `@cert-authority *`
line. The `50-` number sorts the file after the `40-kdn-ssh-access.config` file that `ssh-access`
writes. The aspect reads no `kdn.ssh-access` option, and `ssh-access` reads no `kdn.ssh-ca` option.

### The `kdn-certs ssh login <host>` flow

`packages/kdn-certs/cmd/ssh.go` implements the five steps of design § 7.3:

1. Read the target `ssh-host` leaf and its SSH CA from the declarations.
2. Reuse the named private key, or generate an ed25519 key pair.
3. Sign a user certificate with the SSH CA, with the principal and the short interactive lifetime.
4. Prompt for the YubiKey touch inside the SOPS decrypt of the CA key.
5. Print the `ssh` command and the certificate path.

The sign path is `ssh-keygen -s`, the OpenSSH-native signer. It reads the SOPS-sourced CA key
directly, so it needs no `ca.json` and no provisioner. The `internal/smallstep` package gains the
`SSHSigner` interface, `GenerateSSHKey` and `SignSSH`.

### The test CA

`internal/smallstep/smallstep_test.go` signs a real user certificate and a real host certificate
against a test CA under the test's own `t.TempDir()`, outside `data/`. The test CA key is
unattended, so the suite signs with no YubiKey. The real CA key is never read.

## Verification steps

All commands exit 0:

| Command | Result |
|---|---|
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-ssh-ca'` | the area assertions pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.standalone-aspects'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-coverage'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-eval-guards'` | pass |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.kdn-certs-test'` | the mocked Go suite passes |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.kdn-certs-test-ca'` | the SSH sign cases run against the test CA |

`checks/den-mvp/assertions/ssh-ca.nix` holds one bare-consumer subject per class plus a declared
root CA and an `ssh-host` leaf. `checks/den-mvp/tests.nix` gains `ssh-ca` in the `den-eval-guards`
registry list. The four den entities (`host-nixos`, `host-darwin`, `users/dev`, `home`) name
`kdn.ssh-ca` in their own `includes`, so decision D3 holds with no `den.default`.

## Follow-up notes

**`kdn-certs apply` does not sign SSH leaves yet.** The TLS signer refuses an `ssh-user` or
`ssh-host` leaf with a clear error, and the SSH sign path is wired into `ssh login` alone. The
design § 7 says `apply` signs the host certificate, so the generation loop still needs an SSH
branch. This is a follow-up, not a blocker: the user scoped this sub-task's CLI work to the
`ssh login` flow.

**Per-class lifetimes are CLI flags.** `ssh login` defaults to the short interactive lifetime
`+8h` and takes `--lifetime`. The automation class uses the same sign path with a longer value. The
exact values are a security choice and stay with the task owner.

**`den-eval-instantiate` is unverified on this host** (environmental `aarch64-darwin` pull). The
`ssh-ca` pairs are forced by the same code path; a Darwin host must confirm.
