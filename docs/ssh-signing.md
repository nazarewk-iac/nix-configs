---
type: Guide
description: How to log in to fleet hosts with SSH user certificates signed by the KDN SSH CA instead of per-host authorized_keys entries.
timestamp: 2026-10-12T16:30:00+02:00
authored_by: agent
---

# SSH signing with the KDN CA

The KDN certificate authority (`data/ca/kdn.crt`, the same root as the [zellij-web
certificates](zellij-web-access.md)) also signs SSH certificates. A short-lived user certificate
replaces the per-user `authorized_keys` line; a host certificate lets clients trust every fleet host
by CA instead of by pinned key.

The full design is § 7 of
[docs/tasks/2026-09/declarative-certificates/design.md](tasks/2026-09/declarative-certificates/design.md).
This page is the operator's how-to.

## What is deployed today (2026-10-12)

| Side | Host | State |
|---|---|---|
| Server (`ssh-ca` nixos aspect) | `brys` | live after the 2026-10-12 activation: `TrustedUserCAKeys`, plus a `HostKey`/`HostCertificate` pair for the new `ssh-host-brys` leaf |
| Client (`ssh-ca` homeManager aspect) | `oams`, user `kdn` | live: `~/.ssh/config.d/50-kdn-ssh-ca.config` + `@cert-authority` fragment |
| CA key | `oams` | in `data/ca/kdn.key.sops`, recipients are the two unattended YubiKeys (`yk-oams-unattended`, `yk-brys-unattended`) — signing works headless |

Other hosts gain the same by adding `"ssh-ca"` to their `denLib.imports` aspects and one
`kdn.certificates.certs.ssh-host-<name>` leaf.

## Log in from `oams` to `brys`

One command, run anywhere inside this repo checkout on `oams` while the YubiKey is plugged in:

```bash
kdn-certs ssh login brys
```

It writes `~/.ssh/id_ed25519-cert.pub` (the key itself is generated if missing) — valid for the
`kdn` principal, default lifetime `+8h` — and prints the `ssh` command. Then simply:

```bash
ssh brys
```

No `authorized_keys` entry on `brys` is consulted for this path; `sshd` accepts the certificate
because it was signed by the CA in `TrustedUserCAKeys` and names your login user as a principal.

Flags:

| Flag | Default | Meaning |
|---|---|---|
| `--user <name>` | your local login | remote login the certificate is valid for (a principal) |
| `--lifetime +8h` | `+8h` | OpenSSH validity interval, e.g. `+30d` for an automation token |
| `--key <path>` | `~/.ssh/id_ed25519` | which key to certify; an existing key is reused |

The certificate expires. Re-run `kdn-certs ssh login brys`; nothing else needs a reload.

## Verify

```bash
# the client presents the certificate:
ssh -G brys | grep -i certificatefile
ssh -vv brys true 2>&1 | grep -i 'Offering certificate'

# the host certificate is in force (from any CA-trusting client):
ssh-keygen -F brys -f ~/.ssh/known_hosts.d/50-kdn-ssh-ca -v   # CA trust, not a pinned key

# on brys, sshd says the login came from the CA:
sudo journalctl -u sshd -n 20 | grep -i 'CA SHA256'
```

## Regenerating the host certificate

`hosts/brys/certs/ssh_host_ed25519-cert.pub` is generated, not hand-written:

```bash
nix run .#kdn-certs -- apply        # signs every declared leaf that is missing/expired
```

The host certificate lives 30 days (the automation class, `sshValidityDefault`). `apply` renews it
when expired — same as TLS leaves — and the next activation on `brys` reloads sshd. The private half
goes to `hosts/brys/certs/ssh_host_ed25519.key.sops`, encrypted by the usual `.sops.yaml` rule.

## Security notes

- Old clients that pinned `brys`'s classic host key keep working: OpenSSH
  `prefer_local_hostkeys` makes `sshd` fall back to the raw key for those clients. CA-trusting
  clients verify the host certificate instead.
- The CA private key is currently the **unattended** YubiKey identity. Rotating it to a
  touch-required CA is task
  [007-ca-rotation](tasks/2026-09/declarative-certificates/007-ca-rotation/definition.md) — until
  then, treat a stolen oams-or-brys YubiKey as CA-compromising.
- `@cert-authority *` trusts CA-signed host certificates for **every** hostname, not just fleet
  names. Accepted trade-off inside the network namespaces this CA signs; revisit with a search list
  if that ever widens.
