---
type: Task
description: Replace the manual openssl and YubiKey certificate flow with a declarative CA DAG, a kdn-certs CLI, certificate rotation and SSH certificates.
status: in-progress
authored_by: agent
timestamp: 2026-09-25T17:29:39+02:00
---

# Declarative certificates

## Context

Today a person signs each leaf certificate by hand. The script `hack/kdn-ca-sign.sh` decrypts
`data/ca/ca.key.sops`, runs `openssl`, writes the public certificate and the SOPS key, and verifies
the result against `data/ca/ca.pub` (`hack/kdn-ca-sign.sh:69`). The CA private key needs a YubiKey
touch, so the script stays manual.

The tree holds no declarative layer for certificates. Four hosts consume a zellij web certificate.
Each host names its own file pair at `hosts/<host>/certs/zellij.pub` and
`hosts/<host>/certs/zellij.key.sops` (`hosts/oams/default.nix:347`, `hosts/brys/default.nix:484`,
`hosts/etra/default.nix:448`, `hosts/moss/default.nix:45`). The `kdn.ca` aspect only trusts a CA as
a system CA. It mounts the public certificate and adds it to `security.pki.certificateFiles`
(`modules/den/aspects/ca.nix:100-105`). It never generates a key and never signs a certificate.

Three gaps follow:

1. **No declaration.** A certificate is a file pair, not an option. Nothing enumerates the
   certificates of the tree.
2. **No SSH certificates.** `TrustedUserCAKeys`, `HostCertificate`, `@cert-authority` and
   `CertificateFile` appear nowhere in the tree.
3. **No rotation.** Nothing compares a certificate date against a policy. A person notices an
   expiry by hand.

## Goals

- One declarative layer. An option set holds the CA graph and the leaf certificates.
- One CLI, `kdn-certs`. It walks every target, deduplicates the declarations, and drives
  smallstep.
- A CA DAG. A root signs an intermediate; an intermediate signs a leaf. The CLI sorts the graph
  topologically.
- Rotation. The CLI regenerates a certificate when its date is too old or its issuer does not
  match the declaration.
- SSH certificates. One CA signs SSH user certificates and SSH host certificates.
- One first consumer. The zellij web certificate moves from a manual file pair to a declaration.

## Non-goals

- No change to `kdn.ca`. It keeps its `nixos` class and its system-trust job.
- No change to `kdn-ssh-access`. It picks routes and identities. It does not decide trust.
- No online CA. smallstep runs offline.
- No SSH path through Cloudflare. Cloudflare is a TLS-only fallback.
- No `enable` option. The `standalone-aspects` check forbids a reachable one.
- No automatic activation. The CLI runs on demand.

## Approach

Four den aspects carry the work. All four live in `modules/den/aspects/` and join the registry in
`modules/den/lib.nix`.

| Aspect | Classes | Role |
|---|---|---|
| `kdn.ca-dag` | `nixos`, `darwin`, `homeManager`, `devenv` | Declares the CA DAG option set only. Data lives in `data/`. No generation. |
| `kdn.certificates` | `nixos`, `darwin`, `homeManager`, `devenv` | Declares the leaf option set and wires consumption. Exposes `certPath` and `keyPath`. |
| `kdn.ca-manager` | `devenv` | Puts the `kdn-certs` CLI and the CA DAG into a devenv shell. |
| `kdn.ssh-ca` | `nixos`, `darwin`, `homeManager` | SSH login trust. Server `TrustedUserCAKeys` and `HostCertificate`; client `@cert-authority` and `CertificateFile`. |

`kdn.ca-manager` is separate from the existing `kdn.ca`. Do not redeclare `options.kdn.ca` in the
same class tree.

Every den host, user, home and standalone devenv shell names the aspect in its own `includes`, or
through `denLib.imports { aspects = [ … ]; }`. The design deliberately does **not** use
`den.default` global injection. A universal (old-tree) host reaches the aspect through
[000-universal-augmentation/definition.md](000-universal-augmentation/definition.md). See
[design.md](design.md) § 2.

The storage rule: the public certificate is `<directory>/<certFile>` and it is committed plain.
The private key is `<directory>/<keyFile>.sops` and it is committed as raw/binary SOPS.

The CLI package lives at `packages/kdn-certs/`. It is Go, built with `buildGoModule`, and it
shells out to `step`, `step-ca`, `nix` and `sops`.

## Sub-task index

| # | Task file | Goal |
|---|---|---|
| 000 | [000-universal-augmentation/definition.md](000-universal-augmentation/definition.md) | Verify partial augmentation of a universal host with one den aspect through `denLib.imports`, so a host migrates one aspect at a time. |
| 001 | [001-ca-dag/definition.md](001-ca-dag/definition.md) | Add the `kdn.ca-dag` aspect: the CA graph as data, with no generation and no system trust. |
| 002 | [002-cert-declarations/definition.md](002-cert-declarations/definition.md) | Add the `kdn.certificates` aspect: the leaf option set and the `certPath`/`keyPath` consumption. |
| 003 | [003-ca-manager/definition.md](003-ca-manager/definition.md) | Add the `kdn.ca-manager` aspect: the CLI and the CA DAG in a devenv shell, plus the smallstep lifecycle. |
| 004 | [004-cert-cli/definition.md](004-cert-cli/definition.md) | Add the `kdn-certs` Go CLI: the walk, the dedup, the rotation test and the smallstep driver. |
| 005 | [005-ssh-ca/definition.md](005-ssh-ca/definition.md) | Add the `kdn.ssh-ca` aspect: server trust, client trust, host certificates and the `ssh login` flow. |
| 006 | [006-zellij-migration/definition.md](006-zellij-migration/definition.md) | Replace the manual zellij file pair on four hosts with a `kdn.certificates` declaration. |
| 007 | [007-ca-rotation/definition.md](007-ca-rotation/definition.md) | Rotate the unattended KDN root CA to a touch-required CA, with a migration window for the leaves. |
| 008 | [008-apply-ssh-signing/definition.md](008-apply-ssh-signing/definition.md) | Wire the SSH sign branch into `kdn-certs apply`, so `apply` generates and signs `ssh-user` and `ssh-host` leaves too. |

The umbrella stays `status: in-progress` until every sub-task is `done`.

## Supporting documents

- [research.md](research.md) — the tool decision, the den enumeration model, the SOPS binary-secret
  model and the SSH-cert gap.
- [design.md](design.md) — the full design: the four aspects, the option sets, the CLI, the
  lifecycle, the SSH wiring and the test plan.

## Constraints

- Follow the `standalone-aspects` rule. No reachable `enable`, no `kdnConfig`, no
  `modules/universal` and no `modules/meta`.
- Keep the CA private key out of every running service. Decrypt it on demand only.
- Never cite a fork-only path. The docs go to the public remote.

## Open risk

**UNVERIFIED:** whether a den aspect of class `devenv` reaches a host-derived devenv shell. The
design therefore adds `kdn.certificates` and `kdn.ca-dag` to each standalone devenv shell by hand
(`checks/den-mvp/devenv/default.nix`). A measurement must settle this. Record the result in the
task worklog.

**Resolved 2026-09-25:** nix-darwin declares `services.openssh.extraConfig`, not
`services.openssh.settings`. The `darwin` class writes a `sshd_config` fragment. See
[005-ssh-ca/definition.md](005-ssh-ca/definition.md) and [design.md](design.md) § 7.1.
