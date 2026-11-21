---
type: Solution
description: nixpkgs OpenSSH 10.6p1 serves anji on 2222 with the post-quantum host identity; `ssh anji` and its FQDNs default to it, while `anji+apple` keeps Apple's sshd on 22 for recovery.
task: definition.md
authored_by: agent
timestamp: 2026-11-21T19:00:00+01:00
---

# Solution

## What shipped

- `hosts/anji/default.nix`: `nixpkgsSshdPort = 2222`, the `org.nixos.nixpkgs-sshd` launchd job,
  and `/etc/ssh/sshd_nixpkgs_config`. The job runs through `kdn-nix-darwin-helper`, so `/nix` is
  mounted and the Full Disk Access grant covers the daemon tree.
- Apple's sshd on **22** and Remote Login are unchanged. That keeps the FileVault pre-boot SSH
  unlock and the recovery daemon.
- `data/slots/slots-ssh-access.nix`: `anji` carries its public names and `port = 2222`, the LAN and
  etra edges use 2222, and the etra NetBird edge (`anji.priv…`) is the reliable relay fallback.
- `packages/kdn-ssh-access`: the host `names` and `port` options emit a plain `Host` block for the
  short name and every FQDN; the `+apple` tag forces the final target to port 22. Tests cover the
  tag and the port override.
- `packages/kdn-ssh-access/README.md`: the `+apple` tag and the `names`/`port` host options.

## The explicit include list

The Darwin build of nixpkgs OpenSSH has **no PAM**. Including the whole
`/etc/ssh/sshd_config.d/*.conf` directory pulls in `100-macos.conf`, whose `UsePAM yes` is an
unsupported option. The daemon logged `Unsupported option UsePAM` and did not serve. The nixpkgs
config therefore names only the fleet fragments:

```
Include /etc/ssh/sshd_config.d/050-kdn-authorized-keys-command.conf
Include /etc/ssh/sshd_config.d/099-host-keys.conf
Include /etc/ssh/sshd_config.d/100-nix-darwin.conf
Include /etc/ssh/sshd_config.d/101-authorized-keys.conf
```

It does not set `UsePAM` at all. `100-macos.conf` and `050-kdn-debug.conf` are excluded.

## The application firewall

The macOS application firewall allows incoming connections per binary. Apple's `/usr/sbin/sshd`
is allowed; the nixpkgs `sshd` at a `/nix/store` path is not. The activation adds and unblocks the
exact path with `socketfilterfw`. The path changes with nixpkgs, so the activation re-adds it. A
daemon that started before the rule needs `launchctl kickstart -k system/org.nixos.nixpkgs-sshd`;
the boot order adds the rule before the job starts.

## Measurements (2026-11-21)

- `ssh anji 'echo $SSH_CONNECTION'` → `192.168.73.49 … 192.168.73.85 2222`.
- `ssh anji+apple 'echo $SSH_CONNECTION'` → `192.168.73.49 … 192.168.73.85 22`.
- `ssh -o ControlPath=none -o ControlMaster=no -o HostKeyAlgorithms=ssh-mldsa44-ed25519-cert anji true`
  → `kex: host key algorithm: ssh-mldsa44-ed25519-cert`; server certificate ID `anji`, CA
  `SHA256:hgSW/M0XhoBrKLTZ8h47k3qEV5ADoRTFfwWD22zJkP0`, valid to 2027-02-10.
- The nixpkgs daemon reports `OpenSSH_10.6p1`; `sshd -T` shows `Port 2222`, the ed25519 and
  `mldsa44-ed25519` host keys/certs, and the CA trust.
- `ssh anji.lan.etra.net.int.kdn.im`, the trailing-dot form, and the short `anji` all pass a
  strict connection; the CA verifies the host certificate.
- `ssh anji+apple` and `ssh -p 22 anji` still reach Apple's sshd; Remote Login is On.
- The `kdn-ssh-access` plain `Host` block is in `~/.ssh/config.d/40-kdn-ssh-access.config` on
  `oams`; `ssh -G anji` shows `port 2222`, `ssh -G anji+apple` shows `port 22`.

## Revert

- Client: revert `data/slots/slots-ssh-access.nix` (or remove `anji.names`, `anji.port`, the edge
  ports and the `+apple` block) and rebuild the client. `ssh anji` returns to the old route.
- Host: remove the `nixpkgs-sshd` job and the `sshd_nixpkgs_config` block from
  `hosts/anji/default.nix`, then activate. To stop only the fleet daemon now:
  `sudo launchctl bootout system/org.nixos.nixpkgs-sshd`. Apple's sshd on 22 and Remote Login are
  untouched, so the recovery path remains.
- Firewall: remove the nixpkgs `sshd` entry with
  `sudo socketfilterfw --remove /nix/store/…-openssh-10.6p1/bin/sshd`.

## Acceptance

- `launchctl print system/org.nixos.nixpkgs-sshd` shows the helper as the top-level process and
  the running `sshd` child; `lsof -iTCP:2222` listens on IPv4 and IPv6.
- Remote Login is On; the pre-boot FileVault SSH unlock is untouched.
- `ssh anji` and its FQDNs use 2222; `anji+apple` uses 22.
- The PQ certificate negotiates; the strict connection from `oams` passes; the CA verifies the
  host certificate.
- Boot proof: see below.

## Boot proof

The runtime proof is above. The launchd job uses the same helper and store-mount path as the
nix-daemon, and Apple's sshd on 22 remains the recovery daemon. The reboot proof is recorded in
the worklog of the run that performed it.
