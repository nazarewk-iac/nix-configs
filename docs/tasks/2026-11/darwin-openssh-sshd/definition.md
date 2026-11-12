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

`anji` runs `${pkgs.openssh}/bin/sshd` as the SSH daemon for the booted system, **without
disabling Remote Login**, and the post-boot SSH service still presents the post-quantum host
identity.

The original goal — replace Apple's sshd on port 22 and switch Remote Login off — is **blocked**;
see the constraint below.

## Why

- One sshd version across the fleet: the same configuration, the same algorithms, the same
  failure modes.
- The post-quantum host identity works on the Mac, like the five NixOS hosts.
- `services.openssh.settings` would become usable on darwin, removing the `extraConfig` special
  case from the `ssh-ca` aspect.

## The constraint: remote FileVault unlock (research, 2026-11-12)

`anji` is macOS 27.0.1 (build 26A434), FileVault On, Remote Login On. macOS 26 added FileVault
unlock over SSH at the unified login screen, and the system's own manual states the rule:

```
$ man apple_ssh_and_filevault
The macOS version of OpenSSH stores all of its configuration files, both system-wide and
per-account, in the data volume. Therefore, the usually configured authentication methods and
shell access are not available during this time. However, when Remote Login is enabled, it is
possible to perform password authentication using SSH even in this situation.
```

Three consequences:

- The pre-boot SSH is **Apple's OpenSSH from the sealed system volume**. It cannot read `/etc/ssh`
  or a nixpkgs binary: both live on the data volume, which is still locked. Replacing the running
  system's sshd does not reach it.
- It is gated on **Remote Login** and authenticates with the account **password** (per-account
  `authorized_keys` are on the locked volume too).
- Therefore the original approach — disable Remote Login to free port 22 — would very likely
  remove the only remote unlock path for a Mac with no physical access. **A failed test is
  unrecoverable remotely**, so the change is blocked rather than merely risky.

The feature needs Apple Silicon, macOS 26+, FileVault and Remote Login, all of which `anji` has.

## Approaches, in order of preference

1. **Keep Apple's sshd on 22 and Remote Login on; run nixpkgs sshd on another port.** The pre-boot
   unlock keeps working, and the fleet reaches the PQ identity on the alternate port. Cost: two
   daemons, two configurations, and a port change in the inventory and `Host` blocks.
2. **A launchd job that owns port 22.** Requires Remote Login off, which is now known to remove
   the pre-boot unlock. Blocked.
3. **Keep only Apple's sshd** (status quo). No PQ identity on `anji`, no port change, no risk.

## Risks

- **Lockout, and the pre-boot unlock is the only way back.** `anji` is remote. The change must be applied with a second shell already open, or a
  scheduled `launchctl bootstrap` of Apple's original plist as a revert, and it must be tested
  with `sshd -t` before the switch. Record the exact revert command in the task before running it.
- **macOS updates** may re-enable Remote Login and take port 22 back. The task must state how to
  detect that (a check on `launchctl print system/com.openssh.sshd`, or the owner's shell prompt
  after an update).
- **Key permissions.** `sshd` refuses keys with looser modes; the deployed files are `0400`
  (root:wheel) already, and the PQ file too.
- **The builder guest is unaffected**: it is a NixOS lima VM and already runs nixpkgs OpenSSH.

## Acceptance

1. `launchctl print system/<job>` shows the `${pkgs.openssh}` binary, Remote Login stays On, and
   the pre-boot unlock survives a reboot (verified by rebooting `anji` while a second SSH session
   and a rollback plan are ready).
2. `ssh anji 'sudo sshd -V'` (or the daemon's binary path) reports the fleet's pinned OpenSSH.
3. `ssh -o HostKeyAlgorithms=ssh-mldsa44-ed25519-cert anji true` negotiates
   `ssh-mldsa44-ed25519-cert`, and `sshd -T` shows one `HostKey` per declared identity.
4. A strict connection from `oams` passes, and the CA still verifies the host certificate.
5. A documented revert restores Apple's sshd and Remote Login.

## Out of scope

- Replacing sshd on any other darwin host (there is none).
- Changing the CA or the certificate validity.
- The lima builder guest, which already runs NixOS.
