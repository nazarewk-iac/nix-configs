---
type: Task
description: Finish the Rosetta builder bootstrap on `anji` — run phases 2 and 3, then confirm both Linux architectures build.
status: open
authored_by: agent
timestamp: 2026-10-01T17:38:07+02:00
---

# Finish the Rosetta builder bootstrap on `anji`

## Context

The Rosetta builder gives `anji` a local `aarch64-linux` and `x86_64-linux` builder. Its guest
image is a plain `aarch64-linux` derivation and is not substitutable, so the first build needs a
Linux builder that is already running. The stock `nix.linux-builder` is that builder, but it starts
only at activation. The bootstrap is therefore three switches. The full procedure is in
[docs/multi-arch-builder.md](../../../multi-arch-builder.md), "Bootstrapping the Rosetta builder on
`anji`".

## Work done

Measured on 2026-10-01.

### Phase 1 — complete

`hosts/anji/default.nix` is at phase 1: `legacyLinuxBuilder = true; rosettaBuilder = false;
bootstrapBuilder = true`. The switch reached generation 75. The stock builder runs, and
`/etc/nix/machines` lists it plus `briv`.

### Two blockers fixed

1. **The remote-builder key mode.** `modules/universal/profile/remote-builders/default.nix` wrote
   the builder key as `0440`. OpenSSH refuses a group-readable private key. The mode is now `0400`.
2. **An invalid SSH option.** The `networking/ssh_config/kdn` secret held `WarnWeakCrypto no`,
   which OpenSSH 10.2 rejects. The stanza is gone.

With both fixes, `anji` dispatches a build to `briv` and to the stock builder.

### Full Disk Access

The stock builder's daemon needs Full Disk Access for its bash binary on the external volume. The
grant is in place. The mechanism is in [docs/darwin-quirks.md](../../../darwin-quirks.md).

### External volume auto-unlock

`hosts/anji/default.nix` unlocks and mounts both external volumes at boot. A `preActivation` block
under `lib.mkBefore` runs first, and a launchd daemon re-runs the same script after boot. Both are
idempotent. See [hosts/anji/disks.md](../../../hosts/anji/disks.md).

## Remaining

1. **Phase 2.** Set `legacyLinuxBuilder = true; rosettaBuilder = true; bootstrapBuilder = false`.
   Switch. The build phase dispatches the Rosetta image to the running stock builder. Both guests
   run. This is a long build: the stock builder has one CPU.
2. **Phase 3.** Set `legacyLinuxBuilder = false; rosettaBuilder = true; bootstrapBuilder = false`.
   Switch. The stock builder detaches. The Rosetta guest keeps its already-built image.
3. **Verify.** Both commands must succeed, and `/etc/nix/machines` must list `rosetta-builder` with
   both architectures:

   ```bash
   ssh anji 'nix build --no-link --print-out-paths "nixpkgs#legacyPackages.aarch64-linux.hello"'
   ssh anji 'nix build --no-link --print-out-paths "nixpkgs#legacyPackages.x86_64-linux.hello"'
   ```

## Risks

- The Rosetta guest disk is a sparse file on the internal disk (`100GiB`, capped at `150GiB`). It
  competes with the OS for the 256 GB internal disk. The task
  [rosetta-builder-external-drive](../rosetta-builder-external-drive/definition.md) moves it.
- The stock builder has one CPU, so phase 2 is slow.
- A nixpkgs bump that changes bash needs a new Full Disk Access grant.

## Related docs

- [docs/multi-arch-builder.md](../../../multi-arch-builder.md) — the bootstrap procedure.
- [docs/darwin-quirks.md](../../../darwin-quirks.md) — TCC and the external volume.
- [hosts/anji/disks.md](../../../hosts/anji/disks.md) — the external volumes.
- [rosetta-builder-external-drive](../rosetta-builder-external-drive/definition.md) — the follow-up
  that moves the guest disk.
