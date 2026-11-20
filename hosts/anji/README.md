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

## Recovery console

The NanoKVM at `kvm-2795` is the out-of-band console. Its MCP tools and failure modes are in
[docs/nanokvm.md](../../docs/nanokvm.md). The KVM has no ATX power header on this host: the power
and reset GPIO pulses do nothing, so a power-cycle is a physical action.

## The stable helper

The external store and the launchd daemons are reached through one fixed-path binary with one
Full Disk Access grant. It is now `kdn-nix-darwin-helper`; the older `kdn-nix-bootstrap` path is
the fallback during the rename. The grant rules are in
[docs/darwin-quirks.md](../../docs/darwin-quirks.md).
