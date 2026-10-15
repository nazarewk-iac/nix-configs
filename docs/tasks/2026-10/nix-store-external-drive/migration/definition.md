---
type: Task
description: Migrate the Nix store backing volume of `anji` onto the external USB SSD, gated on a stable bootstrap binary that holds the Full Disk Access grant every launchd daemon needs.
status: in-progress
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

## Cutover runbook (2026-10-14)

The config lives in `hosts/anji/default.nix` behind `storeOnExternal`. With the flag off the host
evaluates and activates exactly as before. Every launchd daemon whose payload is a nix binary
(`nix-daemon`, `activate-system`, `sops-install-secrets`, `rosetta-builderd`, `angrr`, `nix-gc`,
`nix-optimise`, `anji-ext-unlock`) gets `/usr/local/bin/kdn-nix-bootstrap run <label>`;
`darwin-store` becomes `kdn-nix-bootstrap mount-store`. Two details the first draft missed:

- The bootstrap config dir (`/etc/kdn/nix-bootstrap/`) holds **real files** written by the
  activation's `preActivation`, not `environment.etc` symlinks: the symlinks resolve into
  `/nix/store`, which is precisely the volume the bootstrap reads those files before mounting.
- `rosetta-builderd` is launchd socket-activated (fd 3). Go closes inherited descriptors on spawn,
  so the wrapper must not block them. Measured 2026-10-15 on macOS 27.0.1: launchd resolves a
  job's `launch_activate_socket` call for every process of that job, so a plain spawn of
  `rosetta-builderd` from the bootstrap gets the `Sockets.Listener` fd — no descriptor re-pass is
  needed (and launchd does not place the socket at fd 3 for the wrapper, so a re-pass is wrong).

Stage 1 — staged enable (no reboot, store still internal, no grant needed). The swapped plists
run against the internal store because `storeMounted` only asks "is anything mounted at `/nix`",
so this proves the whole wrapper chain while it is still cheap to undo:

```bash
# flip storeOnExternal = true; in hosts/anji/default.nix, then
nix run '.#darwin-rebuild' -- switch remote=anji
ssh anji 'sudo /usr/local/bin/kdn-nix-bootstrap status'          # mounted
ssh anji 'sudo ls /etc/kdn/nix-bootstrap /etc/kdn/nix-bootstrap/jobs'
ssh anji 'nix build nixpkgs#hello --no-link'                     # daemon alive through the swap
```

Stage 2 — owner grant (GUI, on anji). System Settings → Privacy & Security → Full Disk Access →
`+` → `Cmd+Shift+G` `/usr/local/bin/kdn-nix-bootstrap`. Then re-measure the two facts the design
depends on, because `anji` moved to macOS **27.0.1** and the 2026-10-11/12 probes were 26.1:
(a) a granted top-level binary confers access on its whole process tree, (b) the tree reaches USB
volumes. Probe: a temporary `LaunchDaemon` with `ProgramArguments = [/usr/local/bin/kdn-nix-bootstrap,
run, probe]` and a job json `{"argv":["/bin/sh","-c","echo ok > /anji-ext-02/.tcc-probe"]}`;
`launchctl kickstart -k system/…probe`, read the file, then bootout. Never point a probe at
`nix-daemon` — a second daemon re-binds the daemon socket (trap noted above).

Stage 3 — cutover window (owner supervises the reboot):

```bash
# 1. quiesce: no builds running; stop the daemon so the store is frozen
ssh anji 'sudo launchctl bootout system/org.nixos.nix-daemon'
# 2. final sync pass (repeat of stage-0 command below, same excludes)
# 3. flip the /nix line of /etc/fstab to UUID A8D810B7-5177-4930-890A-10CD1BF7AC96
#    (same options: rw,noauto,nobrowse,suid,owners)
# 4. remove the installer leftovers so they cannot crash-loop on the new volume:
#    /Library/LaunchDaemons/systems.lix.nix-installer.nix-hook.plist
#    (it waits on /nix/nix-installer, which the sync copies; repair without a grant would loop)
# 5. sudo diskutil unmount /private/nix-new ; sudo reboot
```

Verify after boot (Acceptance test below): `mount | grep /nix` shows `disk7s2`; daemons running;
`nix build nixpkgs#legacyPackages.x86_64-linux.hello --option substitute false`; `limactl list` +
one ssh-ng build from the Rosetta guest on ext-01; `/run/secrets/kdn` populated.

Rollback until step 7 of the plan is taken: flip the fstab line back, reboot. The plists and the
bootstrap work against whichever volume holds `/nix` — `storeMounted` is volume-agnostic by design.

Sync command used for pass 2 (2026-10-14) — note it mirrors the **whole volume** (`/nix/`), not
just `store`: the volume root also carries `var/` (profiles, gc roots, daemon socket dir) and
`nix-installer`. Pass 1 had copied `store` only.

Stage 0 — done: volume `Nix Store Ext` (disk7s2, unencrypted on the encrypted `anji-ext-02`
container — unlock runs on the container anchor, the ext-02 volume UUID, whose System keychain
item already exists), pass 1 rsync (50 G, 2026-10-13), `packages/kdn-nix-bootstrap`, and the
staged config above.

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
