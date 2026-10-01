---
type: Task
description: Research and decide whether the Nix store on host `anji` can move to an external drive, and record the verdict with evidence.
status: open
authored_by: agent
timestamp: 2026-10-01T17:38:07+02:00
---

# Move the Nix store to an external drive on `anji`

## Context

- Host `anji` is an Apple Silicon Mac mini M2. It has a 256 GB internal disk. It runs
  nix-darwin and Lix 2.95.x.
- The Nix store lives on a dedicated APFS volume named `Nix Store`
  (UUID `b5b3a9c8-86a2-4aff-b45a-bf563b7152a2`) mounted at `/nix`. The Determinate Systems
  nix-installer created this volume.
- `/etc/fstab` mounts it with `UUID=b5b3a9c8-86a2-4aff-b45a-bf563b7152a2 /nix apfs
  rw,noauto,nobrowse,suid,owners`.
- The `Nix Store` volume shares the internal APFS container. So it consumes the 256 GB
  internal disk.
- Two external encrypted APFS volumes exist: `anji-ext-01` and `anji-ext-02`, both 2 TB.
  Both unlock at boot (see [hosts/anji/disks.md](../../../hosts/anji/disks.md)).
- The stock `nix.linux-builder` working directory is already on `/anji-ext-01`. That path
  needs Full Disk Access for the daemon bash binary (see
  [docs/darwin-quirks.md](../../../darwin-quirks.md)).
- [docs/multi-arch-builder.md](../../../multi-arch-builder.md) states the invariant: one
  authoritative `/nix/store` on the host, and disposable builders.

## Problem

The internal disk is small (256 GB). The Nix store grows and competes with the OS. The
external volumes hold 2 TB each and are mostly free. The question is whether the store can
move to an external volume, and at what risk.

## What the research found

This task is a **research and decision** task. It does not change the store. The findings
below come from upstream docs, community reports, and this repository's own measurements.

### What can move, and what is fixed

- The logical path `/nix/store` is **fixed**. Every derivation embeds `/nix/store/...` as a
  literal string in its outputs. The Nix manual states that a store object cannot move to a
  store with a different store directory; it must be rebuilt with all dependencies.
- The **backing volume** can move. The mount point `/nix` stays; the APFS volume mounted at
  `/nix` changes. This is the only viable reading of "move the store", and it needs no
  rebuild.
- `store` in `nix.conf` selects a store URL for a command. It does not relocate the daemon
  store. `NIX_STORE_DIR` changes the store directory, which is the copy-incompatible case.
  Neither helps here.

### The approach

1. Create an APFS volume on the external disk (`diskutil apfs addVolume`).
2. Mount it with `owners`, then `rsync -a` the store so ownership survives.
3. Fix the store directory: `chgrp nixbld store; chmod 1775 store`.
4. Point `/etc/fstab` at the new volume UUID, without `noauto`.
5. Update the launchd mount service (`org.nixos.darwin-store` or
   `systems.determinate.nix-store`) to the new UUID.
6. Delete the old internal `Nix Store` volume in Recovery Mode.
7. Grant Full Disk Access to the nix daemon and the store binaries.

The Determinate installer also has a first-class `--root-disk` option. It places the volume
on another physical disk at install time.

### The leading option — a stable bootstrap binary

TCC evaluates each launchd job by its **responsible process**: the job's top-level program.
A granted top-level binary confers access to its whole process tree. A grant does not cross
a job boundary. Measured on 2026-10-01 with real launchd jobs (see
[docs/darwin-quirks.md](../../../docs/darwin-quirks.md)).

This gives a clean design:

1. Build one **self-contained Go binary** at a fixed path, for example
   `/usr/local/bin/kdn-nix-bootstrap`. A Go binary needs no `/nix/store`.
2. Grant it Full Disk Access **once**. The path never changes, so the grant survives every
   nixpkgs bump.
3. Make it the **top-level program** of every launchd job that touches the external store:
   the unlock job, `nix-daemon`, `activate-system`, and the builders. Each job spawns the
   churning `/nix/store/...` binary as a child.
4. The binary also unlocks and mounts the external store. It runs before `/nix` exists, so
   it breaks the chicken-and-egg: today the unlock is nix-bash code that lives in
   `/nix/store` and cannot run until `/nix` is mounted.

The Nix installer does not manage such a binary. This task must decide whether to add it.

### Blockers

- **TCC / Full Disk Access is the hard blocker.** A launchd daemon on an external volume
  needs `kTCCServiceSystemPolicyAllFiles`. TCC keys on the exact binary path, and each
  nixpkgs bump changes the store path of `bash`. The grant must repeat. This repository
  measured the fragility (see [docs/darwin-quirks.md](../../../docs/darwin-quirks.md)).
  The stable-binary option above removes the repeat.
- **Upstream reports the same failure.** `nix-darwin` issue 1792 reports
  `org.nixos.activate-system` failing with exit 126 on an external store even with Full Disk
  Access. `NixOS/nix` issue 6291 is the same class.
- **Boot ordering.** nix-darwin activation runs *from* `/nix/store`, and
  `org.nixos.activate-system` waits on `/bin/wait4path /nix/store`. The external volume must
  be mounted and decrypted before activation. The mount must be a launchd service ordered
  ahead of `activate-system`, not a `preActivation` step.
- **Encryption.** If the store volume is encrypted, the boot unlock machinery must run
  before the store mounts.
- **Physical presence.** A disconnected or failed drive makes `/nix` vanish. The daemon, all
  nix tools, and activation then break, with no fallback.
- **No bind mount on macOS.** The Linux `mount -o bind` workaround does not exist here. A
  nested mount of an external volume under the boot volume returns `Operation not permitted`
  (measured in this repository).
- **Performance.** An external SSD is slower than the internal NVMe. Nix builds are
  I/O-heavy.

## Proposed approach

1. **Do not change the store yet.** This task produces a decision, not a migration.
2. Confirm the open questions below with real tests on a scratch host or a VM.
3. If the verdict is "proceed", write a separate migration task with the exact steps, a
   rollback plan, and a boot-order proof.

## Open questions

1. Does `--root-disk /dev/diskN` accept an external whole disk and create the volume in its
   container? Does `determinate-nixd init` unlock an encrypted external container from the
   keychain at boot?
2. Which launchd services touch `/nix` on the external volume? Only `nix-daemon`, or also
   `activate-system`, `linux-builder`, and others? Can Full Disk Access go to one stable
   path instead of the churning `/nix/store/...-bash`?
3. Does the Determinate mount service start before `org.nixos.activate-system`? What is the
   failure mode when the drive is slow or absent?
4. Can Full Disk Access re-granting after a nixpkgs bump be automated at all, given SIP
   protects the TCC database? (This repository says no.)
5. Does Lix's installer expose the same `--root-disk` machinery, or only Determinate's?
6. Does an external store change the remote-builder and substituter design of
   [docs/multi-arch-builder.md](../../../multi-arch-builder.md)?
7. What is the measured build-time penalty of an external Thunderbolt SSD against the
   internal NVMe for typical `anji` workloads?

## Verdict so far

**Feasible with caveats, leaning not recommended for this host.** The backing volume can
move. The decisive blocker is TCC plus the upstream `activate-system` failure. The cheaper
alternatives come first: `nix store gc`, `auto-optimise-store`, and tighter `nix.gc` and
`nix.optimise` settings. The large build artifacts already live on the external volumes.

## Related docs

- [docs/darwin-quirks.md](../../../darwin-quirks.md) — TCC on external volumes, encrypted
  volume unlock.
- [hosts/anji/disks.md](../../../hosts/anji/disks.md) — the external volumes.
- [docs/multi-arch-builder.md](../../../multi-arch-builder.md) — the single-store invariant.
- [docs/nix-darwin-getting-started.md](../../../nix-darwin-getting-started.md) — the
  installer and the `/nix` volume.
