---
type: Task
description: Replace Apple's sshd on anji with the pinned nixpkgs OpenSSH, so the Mac presents the post-quantum host identity and runs the same sshd as the fleet.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-11-12T00:00:00+01:00
---

# Run nixpkgs OpenSSH as the sshd on anji

**Solution:** [done.md](done.md). The delivered route is the alternate port: nixpkgs OpenSSH on
2222, Apple's sshd on 22, `ssh anji` and its FQDNs default to 2222, and `anji+apple` /
`anji+recovery` are the recovery aliases on 22.

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

## Incident 2026-11-20 — the lockout is the TCC grant, not the sshd binary

Measured during the recovery:

- `anji` accepted TCP on 22 but sent no SSH banner. The GUI was stuck behind a TCC sheet for a nix
  binary; Finder and Terminal were hung. The login password is
  `pass show hosts/anji/users/kdn/password` (the same account password the pre-boot FileVault SSH
  unlock uses). It unlocked the login screen and publickey worked again.
- The old stable helper's grant was `auth_value=0` in the TCC database. That is the lockout cause:
  the helper that mounts `/nix` and fronts every launchd daemon was denied. The new helper
  (`/usr/local/bin/kdn-nix-darwin-helper`) was installed, granted (`auth_value=2`), and every
  launchd plist was pointed at it. The old `kdn-nix-bootstrap` path remains the fallback.
- The `AuthorizedKeysCommand` was rewritten to a `/bin/sh` script. The previous command had a
  `/nix/store` bash shebang, so key login depended on the store it was meant to recover.
- Apple's sshd 10.3 still logs `Unable to load host key "/etc/ssh/ssh_host_mldsa44_ed25519_key":
unknown or unsupported key type`, so the PQ host identity remains inert on this host. The task
  stay open for the nixpkgs-sshd replacement.

The live launchd plists use the new helper. The normal build is a plain
`nix build .#darwinConfigurations.anji.system` on `oams`: the darwin buildfarm dispatches every
`aarch64-darwin` derivation to `buildfarm-darwin` with no extra flag. A manual build on `anji`
(copy the tree to the Mac and run `nix build` there) is a fallback/recovery step only, for when
the buildfarm is unreachable or the local evaluation source is missing. The system was activated
on 2026-11-21: generation 107,
`/nix/store/axf4jnrx3xmdk30ghhqyjw61500gvq1w-darwin-system-26.11.ff0e21a`. The delivered solution
is in [done.md](done.md).

## State before the solution (2026-11-21)

- Apple's `sshd` 10.3p1 is still the daemon (`/usr/libexec/sshd-keygen-wrapper`); Remote Login
  is On.
- `sshd -T` lists the ed25519 and `mldsa44-ed25519` host keys and certificates, but the daemon
  logs `Unable to load host key ... unknown or unsupported key type` for the PQ key.
- The PQ certificate is valid to 2027-02-10; the ed25519 certificate to 2027-01-13.
- `ssh -o HostKeyAlgorithms=ssh-mldsa44-ed25519-cert anji true` fails with
  `no matching host key type found`; the server offers ed25519 only.
- The port-22 replacement is still blocked by the FileVault pre-boot SSH unlock.
- Decision: **delivered** as nixpkgs sshd on 2222 (approach 1); Apple's sshd keeps 22 for the
  pre-boot unlock and the `anji+apple` / `anji+recovery` recovery aliases. See [done.md](done.md).

## Out of scope

- Replacing sshd on any other darwin host (there is none).
- Changing the CA or the certificate validity.
- The lima builder guest, which already runs NixOS.
