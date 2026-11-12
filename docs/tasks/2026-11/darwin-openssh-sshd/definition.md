---
type: Task
description: Replace Apple's sshd on anji with the pinned nixpkgs OpenSSH, so the Mac presents the post-quantum host identity and runs the same sshd as the fleet.
status: open
authored_by: agent
timestamp: 2026-11-12T00:00:00+01:00
---

# Run nixpkgs OpenSSH as the sshd on anji

## Context

`anji` is the only darwin host in the fleet. Its SSH daemon is **Apple's**:

```
$ launchctl print system/com.openssh.sshd
  program = /usr/libexec/sshd-keygen-wrapper
```

nix-darwin's `services.openssh` writes `/etc/ssh/sshd_config` — that is why the fleet's
`HostKey`, `HostCertificate` and `TrustedUserCAKeys` lines take effect — but it never replaces the
binary.

The consequences measured on 2026-11-12:

- **No post-quantum identity.** The PQ key and certificate are deployed to
  `/etc/ssh/ssh_host_mldsa44_ed25519_key{,-cert.pub}`, `sshd -T` lists them, and the daemon still
  cannot load the key: a client forcing `HostKeyAlgorithms=ssh-mldsa44-ed25519-cert` gets
  `kex: host key algorithm: (no match)`. Apple's OpenSSH has no `mldsa44-ed25519` support.
- **A different OpenSSH version** from the rest of the fleet (Apple's, not the pinned 10.6p1).
- **No `services.openssh.settings` on darwin**, only `extraConfig` — a difference the
  `declarative-certificates` design already records.

## Goal

`anji` runs `${pkgs.openssh}/bin/sshd` as the system SSH daemon on port 22, with the same
`/etc/ssh/sshd_config` nix-darwin generates today, and Apple's Remote Login disabled.

## Why

- One sshd version across the fleet: the same configuration, the same algorithms, the same
  failure modes.
- The post-quantum host identity works on the Mac, like the five NixOS hosts.
- `services.openssh.settings` would become usable on darwin, removing the `extraConfig` special
  case from the `ssh-ca` aspect.

## Approaches, in order of preference

1. **A launchd job that owns port 22.** Disable Apple's Remote Login
   (`sudo systemsetup -setremotelogin off`) so `com.openssh.sshd` stops, then load a nix-darwin
   `launchd.daemons` entry running `sshd -D -f /etc/ssh/sshd_config` with `Sockets` on port 22.
   launchd holds the socket, so the two daemons cannot both own 22 — Apple's must be off first,
   and the switch is one-way until it is re-enabled.
2. **Keep Apple's on 22 and run nixpkgs sshd on another port.** No ownership conflict, but every
   client and the `known_hosts`/pin story changes. Rejected unless (1) proves impossible.
3. **A launchd socket-activated job with a different label on 22.** Same constraint as (1): only
   one job can hold the port.

## Risks

- **Lockout.** `anji` is remote. The change must be applied with a second shell already open, or a
  scheduled `launchctl bootstrap` of Apple's original plist as a revert, and it must be tested
  with `sshd -t` before the switch. Record the exact revert command in the task before running it.
- **macOS updates** may re-enable Remote Login and take port 22 back. The task must state how to
  detect that (a check on `launchctl print system/com.openssh.sshd`, or the owner's shell prompt
  after an update).
- **Key permissions.** `sshd` refuses keys with looser modes; the deployed files are `0400`
  (root:wheel) already, and the PQ file too.
- **The builder guest is unaffected**: it is a NixOS lima VM and already runs nixpkgs OpenSSH.

## Acceptance

1. `launchctl print system/<job>` shows the `${pkgs.openssh}` binary, and
   `launchctl print system/com.openssh.sshd` is absent or `state = not running`.
2. `ssh anji 'sudo sshd -V'` (or the daemon's binary path) reports the fleet's pinned OpenSSH.
3. `ssh -o HostKeyAlgorithms=ssh-mldsa44-ed25519-cert anji true` negotiates
   `ssh-mldsa44-ed25519-cert`, and `sshd -T` shows one `HostKey` per declared identity.
4. A strict connection from `oams` passes, and the CA still verifies the host certificate.
5. A documented revert restores Apple's sshd and Remote Login.

## Out of scope

- Replacing sshd on any other darwin host (there is none).
- Changing the CA or the certificate validity.
- The lima builder guest, which already runs NixOS.
