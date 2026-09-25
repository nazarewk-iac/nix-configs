---
type: Task
description: Add the kdn.ssh-ca aspect for SSH certificate login, with server trust, client trust, host certs, user certs and the kdn-certs ssh login flow.
status: open
parent: ../definition.md
authored_by: agent
timestamp: 2026-09-25T17:29:39+02:00
---

# 005 — SSH CA

Hub: [../definition.md](../definition.md). Depends on
[001-ca-dag](../001-ca-dag/definition.md), [002-cert-declarations](../002-cert-declarations/definition.md)
and [004-cert-cli](../004-cert-cli/definition.md).

Goal: the `kdn.ssh-ca` aspect. It turns the `kdn` CA into an SSH certificate authority. A host then
trusts a user certificate, and a client then trusts a host certificate. No `authorized_keys` entry
and no `known_hosts` entry per host is needed.

The SSH CA serves two consumers:

- **Interactive logins.** A person runs `kdn-certs ssh login <host>`. The command issues a
  short-lived user certificate with principals. `ssh` and the `kdn-*` dispatchers present it.
- **Automation and agents.** CI jobs, remote builders and agents cannot manage long-lived
  `authorized_keys`. They receive their own certificate from the same CA: a user certificate for a
  login, or a host certificate for a builder.

The two classes differ in lifetime. An interactive certificate is short-lived. An automation
certificate may be longer-lived, because an agent cannot renew on demand. Both classes use the same
`TrustedUserCAKeys` trust on the server.

The aspect covers the classes `nixos`, `darwin` and `homeManager`. It declares no `enable` option.
Inclusion is the switch. An empty declaration is the no-op.

The aspect is not injected with `den.default`. `den.default` is deliberately not used. Every host,
user and home names `kdn.ssh-ca` in its own `includes`.

## Server side

The aspect writes two settings into `services.openssh.settings`:

- `TrustedUserCAKeys` names the SSH CA public key. A user certificate that the CA signs then logs
  in, with no per-user `authorized_keys` line. This trust covers both the interactive and the
  automation certificate class.
- `HostCertificate` names the host certificate. The server presents it to every client.

The CA public key comes from `kdn.ca-dag.cas.<name>` with `ssh = true`. The host certificate comes
from `kdn.certificates.certs.<name>` with `type = "ssh-host"`.

## Client side

The aspect trusts the CA on the client, in one of two ways:

- An `@cert-authority` line in `known_hosts`. This trusts every host certificate the CA signs.
- `CertificateFile` in the ssh drop-in. This names the user certificate the client presents.

The drop-in file is `~/.ssh/config.d/50-kdn-ssh-ca.config`. The directory `~/.ssh/config.d/` is the
shared drop-in directory. `program-ssh-client` includes it through
`programs.ssh.includes = [ "~/.ssh/config.d/*.config" ]`. `ssh-access` writes
`40-kdn-ssh-access.config` into the same directory. The `50-` number sorts this file after the
`40-` file.

## Host certs

A host cert is one `kdn.certificates.certs.<name>` leaf with `type = "ssh-host"`. Its
`principals` list holds the host names the certificate is valid for. The `kdn-certs apply` command
signs it. The server reads the public certificate and the decrypted private key.

## User certs, principals and lifetimes

A user cert is one leaf with `type = "ssh-user"`. Its `principals` list holds the login names the
certificate is valid for. The server `TrustedUserCAKeys` trusts the signing CA.

Two classes of user cert share the CA:

| Class | Consumer | Lifetime | Principals |
|---|---|---|---|
| Interactive | `ssh`, `kdn-*` | short, so a stolen certificate expires | the login names of the target |
| Automation | CI, remote builders, agents | longer, because the agent cannot renew on demand | the dedicated service login names |

The plan sets the lifetime per class. The exact values belong to the aspect option set in sub-task
[002 — cert declarations](../002-cert-declarations/definition.md).

## The `kdn-certs ssh login <host>` flow

`kdn-certs ssh login <host>` does five steps:

1. Read the target host and its SSH CA from the certificate declarations.
2. Generate a user key pair, or reuse a named one.
3. Sign a user certificate with the SSH CA. Set the principals to the login names of the target.
   Set the short interactive lifetime.
4. **Prompt for the YubiKey touch.** The CA private key is SOPS-sourced and encrypted to YubiKey
   identities. The sign step blocks until the touch completes. The command waits for the prompt and
   reports a timeout as an error.
5. Write the certificate next to the key and print the `ssh` command.

The command never writes a server file. It only prepares the client side.

## CA private key custody

The CA private key is SOPS-sourced, as `data/ca/ca.key.sops` is today. Real CA operations stay
YubiKey-touch confirmed for now. The signing step prompts for the touch. The plan designs the SOPS
recipient set as a `.sops.yaml` concern, not a code concern, so more decryption candidates can join
later for automation.

A test CA may use an unattended key. The test CA lives outside `data/`, under `checks/` or a temp
directory. It lets the test suite sign without a YubiKey. It never signs a real certificate.

## Orthogonality with `kdn-ssh-access`

`kdn-ssh-access` is orthogonal. It picks routes and identities. It does not decide trust. The
`kdn.ssh-ca` aspect decides trust only. Do not couple the two aspects. Do not read a
`kdn.ssh-access` option from `kdn.ssh-ca`, and do not read a `kdn.ssh-ca` option from
`kdn.ssh-access`.

## Risk — nix-darwin `services.openssh.settings`

**UNVERIFIED:** whether nix-darwin declares `services.openssh.settings`. The `nixos` class sets the
two settings with no doubt. The `darwin` class may not expose the same option. If the option is
absent, the `darwin` class must write the equivalent `sshd_config` fragment another way, or it must
drop the server half. Verify this before the `darwin` work starts. Record the result in the task
worklog.

## Acceptance

- The `nixos` and `homeManager` classes evaluate with a bare consumer.
- The server holds `TrustedUserCAKeys` and `HostCertificate` when the consumer declares the CA and
  the host cert.
- The client writes `~/.ssh/config.d/50-kdn-ssh-ca.config` and the `@cert-authority` line.
- `kdn-certs ssh login <host>` prints a working `ssh` command.
- The interactive and the automation certificate class both pass the server `TrustedUserCAKeys`
  trust.
- The sign step prompts for the YubiKey touch. A timeout is a clear error.
- The test CA signs with an unattended key and needs no YubiKey.
- The `standalone-aspects` check passes. The aspect holds no reachable `enable` option.
- No `kdn.ssh-ca` file reads a `kdn.ssh-access` option, and no `kdn.ssh-access` file reads a
  `kdn.ssh-ca` option.

## Out of scope

Do not change `kdn-ssh-access`. Do not change the `kdn.ca` aspect, which trusts a CA as a system CA.
Do not design the CA DAG or the leaf option set — those are 001 and 002.
