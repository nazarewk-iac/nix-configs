---
type: Task
description: Migrate the Nix store backing volume of `anji` onto the external USB SSD, gated on a stable bootstrap binary that holds the Full Disk Access grant every launchd daemon needs.
status: open
parent: ../definition.md
authored_by: agent
timestamp: 2026-10-11T17:30:00+02:00
---

# Migrate the `anji` Nix store to the external volume

Parent: [../definition.md](../definition.md) — the research that this sub-task executes.

## Owner requirement (2026-10-11)

`anji` must run fully fledged `x86_64-linux` and `aarch64-linux` builds with ~200+ GB of store
growth. The 256 GB internal disk cannot hold OS + host store + builder disks at that size. Builder
guest disks already live on the external volume (`/anji-ext-01/rosetta-builder`, sized 1 TiB by
this change). The host `/nix/store` must move too.

## Measured facts (2026-10-11, real launchd probes on `anji`, macOS 26.1)

| # | Context | Access to a USB volume by a `/nix/store` binary | Result |
|---|---|---|---|
| 1 | launchd job, top-level `/bin/sh` | direct write | allowed (Apple platform binary) |
| 2 | launchd job, top-level `/nix/store/.../bash` | direct write | **blocked (EPERM)** |
| 3 | launchd `/bin/sh -c "exec /nix/store/.../bash"` | write | **blocked** |
| 4 | launchd `/bin/sh` → forked `/nix/store/bash` child | write | **blocked** |
| 5 | mount option `nobrowse` | any of the above | no change |
| 6 | user login context (ssh session) | `/nix/store/bash` write | allowed |
| 7 | throughput, external ext-02 | `dd oflag=sync` 2 GiB | 590 MB/s (internal: 1.7 GB/s) |

Both external SSDs enumerate as **USB** (`diskutil info` → `Protocol: USB`, `Removable Media:
Fixed`). That combination is what TCC's removable-volume policy gates. The existing builder daemons
work on the external volume only because their responsible nix bash path holds an FDA grant — and
per `docs/darwin-quirks.md` that grant must be re-made whenever nixpkgs changes the path.

Probe hazard, measured the hard way (2026-10-11): launching a second `nix-daemon` from a probe job
re-binds `/nix/var/nix/daemon-socket/socket` and orphans the real daemon's listener — every client
then fails with "could not connect to any lix socket" even though the daemon process looks healthy.
Recovery: `launchctl kickstart -k system/org.nixos.nix-daemon`. Probes must exercise file access
only, never a live daemon.

## Consequence

The store volume can move, but every launchd job whose process image is a nix binary must not be
the gated party. That is exactly the **stable bootstrap binary** the parent research named as the
leading option, and the probes above are what promote it from idea to requirement.

## Design

1. `packages/kdn-nix-bootstrap/`: a small self-contained Go binary installed at the fixed path
   `/usr/local/bin/kdn-nix-bootstrap` (Go needs no `/nix/store`).
   - `kdn-nix-bootstrap mount-store`: unlocks the external APFS container (`/usr/bin/security` +
     `/usr/sbin/diskutil`, both Apple binaries) and mounts the store volume at `/nix`. No `/nix`
     dependency — this also kills the chicken-and-egg the parent research flagged.
   - `kdn-nix-bootstrap run <job-name>`: waits for `/nix/store`, reads the job's real payload
     (binary + args) from a generated config file, spawns it as a child, supervises it.
2. Grant FDA once to `/usr/local/bin/kdn-nix-bootstrap`. Per `docs/darwin-quirks.md`, a grant to a
   job's top-level binary confers access on its whole process tree — the probes confirm the tree
   model holds for granted binaries (only platform-binary parents fail to confer).
3. Rewrite the launchd jobs that touch `/nix` on the external volume — `nix-daemon`,
   `activate-system`, `sops-install-secrets`, the builder daemons, `angrr`, `nix-gc`,
   `nix-optimise` — top-level `/usr/local/bin/kdn-nix-bootstrap run <name>`. nix-darwin already
   regenerates these plists; the swap lives in the `nix-config` aspect, guarded by a host option.
4. Migration cutover (all steps reversible until step 7):
   1. `diskutil apfs addVolume` a new volume (`Nix Store Ext`) on the `anji-ext-02` container
      (disk7 — empty, keeps builder I/O on ext-01 and the store on ext-02 separate).
   2. Mount it (e.g. `/private/nix-new`), `rsync -aHAX` `/nix/store`, `chgrp nixbld`, `chmod 1775`.
   3. Second rsync pass with `--delete` to catch the delta.
   4. Flip `/etc/fstab` to the new UUID (`rw,noauto,nobrowse,suid,owners`), point
      `org.nixos.darwin-store` (or the bootstrap) at it, activate, **reboot**.
   5. Verify: boot chain, daemon builds, substitutions, `limactl` guest starts from ext-01.
   6. Soak ≥ 1 week with the old internal volume untouched as rollback (restore = flip fstab +
      plists back via one activation from git).
   7. Delete the old internal `Nix Store` volume (reclaims 54+ GB), only after the soak.

## Acceptance test

1. A launchd-only boot (no user login) reaches `running` with nix-daemon serving builds from the
   external store: `nix build nixpkgs#legacyPackages.x86_64-linux.hello` with `--option substitute
   false` after a cold reboot.
2. One Full Disk Access grant (the bootstrap path) covers every nix daemon job; no per-store-path
   grants remain.
3. A nixpkgs bump changes zero TCC grants: re-run the probe set from `docs/darwin-quirks.md`.
4. Drive-absent boot: macOS still boots to a login prompt; the bootstrap waits (does not crash-loop
   past a threshold); re-plugging recovers without activation.

## Risks

- The macOS user-context grant model can change with a major OS release; the probe plists in this
  task's directory re-measure it in minutes.
- 590 MB/s sync vs 1.7 GB/s internal — builds become I/O bound on the store (~3x at worst).
  Accepted: without the move the builds do not fit at all.
- Physical presence: a unplugged/cabled-bad drive stops all nix. macOS itself stays alive.
- `kdn-nix-bootstrap` becomes a boot-critical component: it needs tests and a reviewed source
  (small, single-purpose Go, per `AGENTS.md` packaging patterns).

## Out of scope

- `x86_64` instruction completeness: Rosetta 2 has no AVX/AVX512. "Fully fledged x86 builds" that
  need AVX will still fail inside the guest — separate decision (TCG qemu guest, or a real x86
  host). This task only sizes and locates storage correctly for whichever builder the owner picks.
- Any other host.

## Related

- Parent research: [../definition.md](../definition.md)
- `docs/darwin-quirks.md` — TCC responsible-process model, measured before.
- `hosts/anji/disks.md` — volumes, UUIDs, unlock procedure.
- `docs/multi-arch-builder.md` — the single-store invariant.
