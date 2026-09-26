---
type: Reference
description: The external disks of the anji host — their volumes, UUIDs, mount paths, and the unlock and auto-unlock procedure.
timestamp: 2026-10-01T14:58:34+02:00
---

# anji disks

`anji` is an Apple Silicon Mac mini M2 with a 256 GB internal disk. Two encrypted external APFS
volumes hold the large data:

| Volume | UUID | Mount path | Holds |
|---|---|---|---|
| `anji-ext-01` | `E630CAE6-D3FB-44C1-9B38-F6211F128B79` | `/anji-ext-01` | the stock `nix.linux-builder` working directory |
| `anji-ext-02` | `14E59EC3-0C46-4D5C-9CCE-B3D716896F14` | `/anji-ext-02` | the UTM disks |

Both volumes are encrypted APFS. `/etc/fstab` mounts them with `noauto,nobrowse,suid,owners`.

## Unlock and mount

An unmount of an encrypted APFS volume also locks it. Unlock before the mount:

```bash
ssh anji 'sudo diskutil apfs unlockVolume anji-ext-01 -nomount \
  && sudo diskutil mount anji-ext-01 \
  && df -h /anji-ext-01'
```

The passphrase is in the owner's KeePass. `diskutil` prompts for it. The general mechanism is in
[docs/darwin-quirks.md](../docs/darwin-quirks.md), "An encrypted APFS volume locks on unmount".

## The stock builder needs Full Disk Access

The stock `nix.linux-builder` working directory is `/anji-ext-01/linux-builder`. macOS TCC blocks a
launchd daemon from an external volume unless the daemon's binary holds Full Disk Access. The
builder daemon fails with `Operation not permitted` without the grant.

The grant is keyed to the exact `bash` store path. After each nixpkgs bump that changes `bash`,
grant Full Disk Access again to the new path:

```
/nix/store/<hash>-bash-<version>/bin/bash
```

Find the path in the builder's log:

```bash
ssh anji 'sudo head -1 /nix/store/*-linux-builder-start'
```

Then add it in System Settings → Privacy & Security → Full Disk Access. The full mechanism and the
failed workarounds are in [docs/darwin-quirks.md](../docs/darwin-quirks.md), "Full Disk Access
gates an external volume".

## Auto-unlock at boot

`hosts/anji/default.nix` unlocks and mounts both volumes at boot. The block sits in
`system.activationScripts.preActivation.text` under `lib.mkBefore`. It reads each passphrase from
the System keychain and pipes it to `diskutil -stdinpassphrase`.

`mkBefore` is required. nix-darwin's `nix.linux-builder` writes `mkdir -p
/anji-ext-01/linux-builder` into `preActivation`, and the activation script runs with `set -e`. An
unmounted volume exposes its mount point on the read-only system volume, so that `mkdir` fails and
aborts the whole activation. The unlock block must run first.

Store one item per volume in the System keychain, keyed by the volume UUID. Use the value form,
with the keychain path last:

```bash
read -rs PW
sudo security add-generic-password -s "<volume-UUID>" -a "<volume-UUID>" \
  -T /usr/bin/security -U -w "$PW" /Library/Keychains/System.keychain
unset PW
```

The `-T` value is `/usr/bin/security`, not `/usr/sbin/diskutil`: the activation script reads the
item with `security`, and `diskutil` does not read the keychain itself. The general mechanism is in
[docs/darwin-quirks.md](../docs/darwin-quirks.md), "The login keychain is locked over SSH".
