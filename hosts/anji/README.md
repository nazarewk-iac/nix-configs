---
type: Reference
description: The anji host entry point — credential locations, the recovery console, and the documents that hold the full detail.
timestamp: 2026-11-20T08:30:00+01:00
authored_by: agent
---

# anji

`anji` is the Apple Silicon Mac mini M2. It is the only Darwin host in the fleet. This file records
where its credentials live; the disk layout is in [disks.md](disks.md) and the non-default macOS
settings are in [bootstrap.md](bootstrap.md).

## Credential locations

| Purpose                              | Location                                                                 | Notes                                                                                                                                                                                                 |
| ------------------------------------ | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| User login                           | `pass show hosts/anji/users/kdn/password`                                | The `kdn` account password. The same value logs in at the GUI and over SSH.                                                                                                                           |
| FileVault unlock (FDE)               | the same `pass` entry                                                    | `anji` has one human account, so its account password is the FileVault credential. The pre-boot SSH unlock at the unified login screen uses the account password too (`man apple_ssh_and_filevault`). |
| External volume `anji-ext-01` unlock | macOS System keychain on `anji`, generic-password item keyed by its UUID  | UUID `E630CAE6-D3FB-44C1-9B38-F6211F128B79`. The `anji-ext-unlock` launchd job and the activation script read it.                                                                                     |
| External volume `anji-ext-02` unlock | macOS System keychain on `anji`, generic-password item keyed by its UUID  | UUID `14E59EC3-0C46-4D5C-9CCE-B3D716896F14`. This item also unlocks `Nix Store Ext` (`/nix`), because that volume is unencrypted inside the ext-02 container.                                          |
| Manual/offline copy of the disk keys | the owner's KeePass                                                      | This is the fallback for a manual `diskutil` unlock when the System keychain is unavailable. The `pass` entries `luks/ext-01-faro/passphrase` and `luks/ext-02-faro/passphrase` are **different** volumes, not these. |

Read a System-keychain item without printing it:

```bash
ssh anji 'sudo security find-generic-password -s <volume-UUID> -a <volume-UUID> \
  -w /Library/Keychains/System.keychain'
```

The 2026-11-20 SSH lockout was recovered with the `pass` entry above. The exact recipe and the
secret-handling rule are in
[docs/tasks/2026-10/nanokvm-mcp-macos-control/definition.md](../../docs/tasks/2026-10/nanokvm-mcp-macos-control/definition.md),
"Findings from the 2026-10-16 password run (run 3)". That session (`ses_ebcb73c34ffec6ZLNGEYVUTBiW`)
used `pass show hosts/anji/users/kdn/password`; it did not change the password.

## SSH daemons

- `org.nixos.nixpkgs-sshd` — nixpkgs OpenSSH 10.6p1 on **2222**. It serves the fleet host
  certificates (ed25519 and `ssh-mldsa44-ed25519-cert`) and the CA trust. The launchd job runs
  through `kdn-nix-darwin-helper`, so `/nix` is mounted and the Full Disk Access grant covers it.
- Apple's sshd on **22** and Remote Login stay on. This is the FileVault pre-boot unlock path and
  the recovery daemon.
- `ssh anji` and its FQDNs default to 2222 through the `kdn-ssh-access` plain `Host` block.
  `ssh anji+apple` and `ssh anji+recovery` (or `ssh kdn-anji+apple` / `kdn-anji+recovery`) use
  Apple's daemon on 22.
- The nixpkgs Darwin build has no PAM. The nixpkgs config includes only the fleet fragments, not
  `100-macos.conf`; do not add `UsePAM` to it.
- The application firewall allows the nixpkgs `sshd` binary separately from Apple's. The
  activation re-adds it; if the daemon started before the rule, run
  `sudo launchctl kickstart -k system/org.nixos.nixpkgs-sshd`.

```bash
ssh anji             # fleet sshd, 2222, PQ host identity
ssh anji+apple       # Apple's sshd, 22, recovery
ssh anji+recovery    # the same recovery path, easier to discover
```

## Recovery console

The NanoKVM at `kvm-2795` is the out-of-band console. Its MCP tools and failure modes are in
[docs/nanokvm.md](../../docs/nanokvm.md). The KVM has no ATX power header on this host: the power
and reset GPIO pulses do nothing, so a power-cycle is a physical action.

## Build and activate

No owner approval is required to build or activate `anji`; an agent may do both. The normal route
is from `oams`:

```bash
nix build .#darwinConfigurations.anji.system
ssh anji 'sudo nix-env -p /nix/var/nix/profiles/system --set <store-path> \
  && sudo <store-path>/activate'
```

The plain `nix build` uses the darwin buildfarm (`buildfarm-darwin`) automatically. No
`--builders`, `--store` or `--max-jobs` flag is needed. The only local prerequisite is that the
evaluation source (`devenv-nixpkgs-patched`) is in the local store; a cold store can fail before
the build hook is consulted.

A manual build on `anji` is a **fallback/recovery step only**. Use it when the buildfarm is
unreachable or the local evaluation source is missing:

```bash
rsync -a --exclude='/.cache' --exclude='/.git' --exclude='/.flake.patches' \
  ./ anji:/Users/kdn/nix-configs-src/
ssh anji 'cd /Users/kdn/nix-configs-src \
  && nix build --print-out-paths --no-link "path:$PWD#darwinConfigurations.anji.system"'
```

The current generation on 2026-11-21 is 105, built from
`/nix/store/dazc1g2l2x5dpn40xzlk9cm8riy4jyhz-darwin-system-26.11.ff0e21a`.

## The stable helper

The external store and the launchd daemons are reached through one fixed-path binary with one
Full Disk Access grant. It is now `kdn-nix-darwin-helper`; the older `kdn-nix-bootstrap` path is
the fallback during the rename. The grant rules are in
[docs/darwin-quirks.md](../../docs/darwin-quirks.md).
