---
type: Reference
description: General macOS-only behaviours that a Linux habit does not predict, with the mechanism and the fix.
timestamp: 2026-10-01T14:58:34+02:00
---

# Darwin quirks

This file records general macOS-only behaviours that this repository met. Each entry states the
symptom, the cause, the evidence, and the fix. Host-specific values live in the host's own
document — for example [hosts/anji/disks.md](../hosts/anji/disks.md). The agent rule
[darwin-quirks.md](../.agents/rules/darwin-quirks.md) says when to add an entry here.

## Full Disk Access gates an external volume

**Symptom.** A launchd daemon reads and writes its working directory on an internal disk. The same
daemon fails on an external APFS volume with `Operation not permitted`. The same command from an
SSH session succeeds.

**Cause.** macOS TCC (Transparency, Consent, and Control) protects an external volume. The service
is `kTCCServiceSystemPolicyAllFiles`, also named Full Disk Access. A process needs this grant to
touch the volume. An SSH session inherits the grant of `sshd`. A launchd daemon does not.

**TCC keys on the binary path, not the user or the parent.** Each nixpkgs bump changes the store
path of `bash`. TCC then sees a new binary and denies it. The old path keeps its grant. This makes
a manual grant fragile.

**Evidence.** Measured on 2026-09-26. Every test ran as root, in the same directory, with the same
uid. Only the binary changed the result:

| Binary | Internal disk | External volume |
|---|---|---|
| denied `bash` | write OK | write **denied** |
| allowed `bash` | write OK | write OK |
| `/bin/sh` (platform binary) | write OK | write OK |

The TCC database shows the grant state. `auth_value=2` allows. `auth_value=0` denies:

```bash
sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' \
  "select auth_value, client from access where service='kTCCServiceSystemPolicyAllFiles';"
```

**Workarounds that fail.** Each one was tested with a real launchd daemon:

- A symlink from an internal path to the external path. TCC resolves the real path.
- A nested mount of the volume under the boot volume. `mount_apfs` returns `Operation not permitted`.
- `exec` of the denied binary from `/bin/sh`. TCC checks the executed binary, not the parent.
- A hard link to the external volume. The volumes differ, so the link fails.

**Fixes.** Two routes exist:

1. Move the working directory to the internal disk. No grant is needed. This route survives a
   nixpkgs bump.
2. Grant Full Disk Access to the exact binary path. The owner does this by hand in System Settings,
   because SIP protects the TCC database from a script. Repeat the grant after each nixpkgs bump
   that changes `bash`.

## The login keychain is locked over SSH

**Symptom.** `security add-generic-password` prints a usage message or fails with
`User interaction is not allowed`. No prompt appears.

**Cause.** An SSH session has no GUI login. The login keychain stays locked. `security` cannot
prompt. The System keychain stays unlocked and writable by root.

**Check the state:**

```bash
security show-keychain-info ~/Library/Keychains/login.keychain-db   # locked over SSH
security show-keychain-info /Library/Keychains/System.keychain      # unlocked
```

**Fix.** Target the System keychain. Put the keychain path last, and give the value to `-w`:

```bash
sudo security add-generic-password -s "<service>" -a "<account>" \
  -T /usr/sbin/diskutil -U -w "<passphrase>" /Library/Keychains/System.keychain
```

**Option order matters.** `security` accepts the prompt form (`-w` last, no keychain path) only
with a terminal. Over SSH the prompt form fails. The value form needs the keychain path last.

**`-w` takes the next word as the value.** In the value form, `-w` consumes the word that follows
it. A command that writes `-w /Library/Keychains/System.keychain` with no real value stores the
path string as the password, and the item goes to the default keychain. Always pass a real value to
`-w`, and put the keychain path last.

**`-A` against `-T`.** `-A` lets any process read the item with no prompt. `-T <binary>` scopes the
read to that binary. Use `-T`. A `-T` item reads back empty through `security
find-generic-password` when the trusted binary is a different one, because the ACL allows only the
named binary. That result is correct.

## An encrypted APFS volume locks on unmount

**Symptom.** After `diskutil unmount`, the volume is locked. A later `diskutil mount` fails with
`This is an encrypted and locked APFS Volume`.

**Cause.** An unmount of an encrypted APFS volume also locks it. The passphrase is then required
again.

**Fix.** Unlock before the mount:

```bash
sudo diskutil apfs unlockVolume <volume> -nomount && sudo diskutil mount <volume>
```

**Auto-unlock at boot.** `diskutil` does not read the keychain itself. It prompts, or it reads a
passphrase from stdin with `-stdinpassphrase`. So the boot script reads each passphrase with
`security` and pipes it to `diskutil`. Store the item in the System keychain, keyed by the volume
UUID, because the login keychain is locked before login. `diskutil` also accepts a keychain file
with `-recoverykeychain` for an Institutional Recovery Key.

**An unmounted volume exposes a read-only mount point.** When a volume is unmounted, its mount
point directory sits on the read-only system volume. A `mkdir` under that path fails with
`Read-only file system`. A boot script that prepares the mount point must unlock and mount the
volume first. In nix-darwin, use `lib.mkBefore` on `system.activationScripts.preActivation.text`
to order the unlock before any other `preActivation` writer.
