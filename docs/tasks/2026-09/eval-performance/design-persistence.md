---
type: Design
description: How to break the persistence read-back — the NixOS side stops reading Home Manager and persists bucket-level base directories plus a short exception list.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T10:05:00+01:00
---

# Persistence without reading Home Manager

`modules/universal/disks/config.nix` builds the boot-time `preservation` mounts from
`config.home-manager.users`, so the parent evaluation forces every Home Manager user. This is the
edge that blocks the split in [hm-split.md](hm-split.md). This design removes it: the machine layer
keeps a **bucket-level base policy** plus a short exception list, all host data, and Home Manager
writes files only.

The note supersedes one line of the earlier inventory: the parent does **not** read `home.file` or
`home.directories`. It reads the `kdn.disks.persist` lists. That is a much smaller surface.

## The defect, exactly

| Site                                         | Reads                                                     | Needed for                                   |
| -------------------------------------------- | --------------------------------------------------------- | -------------------------------------------- |
| `modules/universal/disks/config.nix:43`      | `hmConfig.kdn.disks.persist.<bucket>.{files,directories}` | the `preservation.preserveAt` user entries   |
| `modules/universal/disks/config.nix:135`     | the attribute names of `home-manager.users`               | `kdn.disks.users`                            |
| `modules/universal/disks/config.nix:136-146` | `hmConfig.home.username`                                  | `systemd.services.home-manager-<user>` order |
| `modules/den/aspects/disks.nix:73,777`       | `config.home-manager.users` and the same persist lists    | the same three things                        |
| `modules/den/aspects/disks.nix:836-846`      | the user names and `home.username`                        | the same two things                          |

Two facts make this tractable:

1. **No Home Manager code reads `kdn.disks.persist`.** Every Home Manager occurrence is an
   assignment. The only reader is the parent, at `config.nix:43`. So the option can stop existing in
   the user scope with no HM consumer to update.
2. **`kdn.disks.enable` has no Home Manager consumer either.** The parent forwards it at
   `config.nix:15`; nothing reads it. Den already dropped that forward
   (`modules/den/aspects/disks.nix:28`).

So the host needs three facts from the user graph: the user names, one path list per bucket, and the
systemd unit names. Two of the three are host data already (`config.users.users`).

## What the persist data looks like today

`preservation.preserveAt.<bucket>.users.<user>` merges three layers at `config.nix:34-71`:

| Layer                                             | Owner        | Example                                        |
| ------------------------------------------------- | ------------ | ---------------------------------------------- |
| `kdn.disks.userDefaults.persist` (den only today) | host         | `.cache/nix`, `Downloads`, the four media dirs |
| `hmConfig.kdn.disks.persist.<bucket>`             | **the user** | `.cache/zellij`, `.aws`, `.gnupg`              |
| `kdn.disks.persist.<bucket>.users.<user>`         | host         | a per-user path a host names directly          |

The `kdn.apps` registry is the largest writer: each app declares `dirs` and `files` per bucket, and
`modules/universal/apps/default.nix:111-160` writes all twelve lists into `kdn.disks.persist` from
the `ifHM` branch. `modules/den/aspects/apps.nix` publishes the same data as
`kdn.apps-persist` and asks the consumer to wire it.

**The key observation.** `modules/universal/apps/default.nix:60-71` prefixes every list with a fixed
directory:

| Bucket         | Prefix         |
| -------------- | -------------- |
| `usr/cache`    | `.cache`       |
| `usr/config`   | `.config`      |
| `usr/data`     | `.local/share` |
| `usr/state`    | `.local/state` |
| `disposable`   | none (`""`)    |
| `reproducible` | none (`""`)    |

So **every app entry for the four `usr/*` buckets already sits inside one XDG base directory**. The
per-program lists add no information to a host that persists those directories. The `disposable`
bucket is rolled back to `@empty` on every boot (`config.nix:150-205`), so an entry there does
nothing. The `reproducible` bucket takes no snapshots and nearly every app declares it empty; the one
non-empty entry (`nextcloud-client`, `Nextcloud`) is a home-root path and joins the exception list.

That is the design opening: make the four XDG directories the unit of persistence, and the largest
writer disappears without a migration.

## Why the loop exists

The current model treats Home Manager as the machine's source of truth for _which user paths
matter_. That is a reasonable choice for one evaluation, and a fatal one for two: a boot-time mount
cannot depend on a user's evaluation. Den hit the same wall and named it
(`modules/den/common/persist.nix:16-17`). The fix is not to make the read cheaper. The fix is to
stop needing the answer on the host, or to declare it on the host.

## Candidate designs

### R0 — keep the read-back

Cost: the parent forces the whole user graph. This is exactly the blocker in
[hm-split.md](hm-split.md), and it makes exit criterion 1 harder. Rejected as the end state; it stays
as the fallback until a design lands.

### R1 — bucket-level base directories, plus a short exception list (recommended)

The host persists a fixed set of home directories for every user in `kdn.disks.users`. Each one
maps to a bucket, so the existing snapshot policy still applies. A path outside the base set is an
explicit host entry, written by the module that knows it, in that module's **host** branch.

| Base entry                                                | Bucket                                 | Covers                                                          |
| --------------------------------------------------------- | -------------------------------------- | --------------------------------------------------------------- |
| `.config`                                                 | `usr/config`                           | every `dirs.config` and `files.config` app entry                |
| `.local/share`                                            | `usr/data`                             | every `dirs.data` and `files.data` app entry                    |
| `.local/state`                                            | `usr/state`                            | every `dirs.state` and `files.state` app entry                  |
| `.cache`                                                  | `usr/cache`                            | every `dirs.cache` and `files.cache` app entry                  |
| `Documents`, `Desktop`, `Pictures`, `Videos`, `Downloads` | `usr/data`, `Downloads` in `usr/cache` | the media dirs `disks/default.nix:604-616` writes today         |
| `.ssh`, `.gnupg`                                          | `usr/data`                             | keys and trust stores, currently at `ssh-client:31`, `gnupg:93` |

After that set, the whole `kdn.apps` persist output and about 90 % of the per-program writes become
unnecessary. The survivors are the paths outside the four XDG directories:

| Survivor                                                                | Where it lives today                                | Replacement                    |
| ----------------------------------------------------------------------- | --------------------------------------------------- | ------------------------------ |
| `.aws`                                                                  | `development/cloud/aws:16`                          | host branch of the same module |
| `.java/.userPrefs/...`                                                  | `development/jetbrains:158-161`                     | host branch of the same module |
| shell histories (`.bash_history`, `.zsh_history`, `.python_history`, …) | `profile/machine/baseline:120-125`                  | base entry or host branch      |
| `dev`, `Games`                                                          | `profile/user/kdn:296`, `profile/machine/gaming:84` | host branch or per-user entry  |
| `Nextcloud`                                                             | `nextcloud-client:41` (`usr/reproducible`)          | host branch                    |

Cost: more data persists. `.config` now persists whole, including generated files that used to be
left out. That is the normal impermanence trade-off; the four buckets still separate the snapshotted
halves (`config`, `data`) from the disposable ones (`cache`, `state`).

The switch itself needs one reboot. On a live system the old per-file mounts sit _inside_ the new
directory mount, so they stack until the old units and mounts are gone. Plan a `nixos-rebuild boot`
plus a reboot, and verify `findmnt` shows one mount per base directory afterwards.

### R2 — the selection becomes host data

Keep per-program granularity, and move the _selection_ (`kdn.apps.<name>.enable`) into host data that
both evaluations read. The host renders persistence from it; the user side renders packages and
files from the same data.

Cost: the user's app selection leaves the Home Manager config, which is where it is convenient. It
is the exact-semantics answer for an adopter who refuses R1's broader persistence. Keep it as an
escape hatch for a host with a strong "never persist this" rule, not as the default.

### R3 — the wrapper joins the two evaluations

The wrapper evaluates the user configs, extracts `kdn.disks.persist` as JSON, and passes it to
`nixos-rebuild` as an argument or a generated file. It keeps today's ergonomics, and it is worse in
every other way: the parent's evaluation depends on a file produced by a previous evaluation, CI
cannot build the parent alone, and an HM-only edit now invalidates the parent. Rejected.

## R1 in detail

### Schema changes

Universal has no `kdn.disks.userDefaults.persist`; den does (`modules/den/aspects/disks.nix:273`)
and documents the exact move (`disks.nix:31-35`). Port it. The resulting merge in
`preservation.preserveAt` is:

```nix
# schematic, not an exact helper call
users = builtins.mapAttrs (username: _user: {
  files = merge [ userDefaults.persist.<bucket>.files baseFiles ];
  directories = merge [ userDefaults.persist.<bucket>.directories baseDirs ];
}) cfg.users;   # host data, no config.home-manager.users
```

`cfg.users` stops defaulting from `home-manager.users`. Default it from `config.users.users` — the
module already reads that option at `config.nix:211-239` for the home directory, mode, user and
group — and keep an explicit entry for a user whose home location differs. `root` needs a decision:
it is not a normal user, but it has a Home Manager config on some hosts.

### The base set is a policy, so it lives in the machine layer

`modules/universal/disks/default.nix` (host branch) declares the base entries once, next to the
existing `kdn.disks.base` bucket declarations. A module that needs an exception writes it in its own
host branch:

```nix
# modules/universal/programs/gnupg/default.nix, host branch
config = kdnConfig.util.ifTypes [ "nixos" ] {
  kdn.disks.userDefaults.persist."usr/data".directories = [
    { directory = ".gnupg"; mode = "0700"; }
  ];
};
```

This is one line per program, local to the file, and it never crosses an evaluation.

### The writes to delete

| Kind                                                          | Count (approx.) | Action                                                       |
| ------------------------------------------------------------- | --------------- | ------------------------------------------------------------ |
| `kdn.apps` → `kdn.disks.persist`                              | 12 lists        | Delete. All four `usr/*` buckets are covered by the base set |
| Per-program `ifHM`/`sharedModules` writes inside XDG          | ~35             | Delete                                                       |
| Per-program writes outside XDG                                | ~10             | Move to the module's host branch                             |
| `disks/default.nix:575-616` sharedModules base                | 7 paths         | Move to `userDefaults.persist`                               |
| `disks/config.nix:15` `kdn.disks.enable` forward              | 1               | Delete                                                       |
| den aspect writes (`profile-*`, `zellij`, `gnupg`, `apps`, …) | ~15             | The same, per aspect                                         |

### The service ordering

`systemd.services.home-manager-<user>` is ordered `after = preservation.target` at
`config.nix:136-146`. The name is `home-manager-<username>`, and the username is host data. Iterate
`cfg.users` instead of `config.home-manager.users`. In the split end state the parent owns no Home
Manager service, so the block disappears with the nested module.

### Atuin, the one other read

`modules/universal/programs/atuin/default.nix:268,302` builds a script path from
`home-manager.users.<user>.xdg.dataHome`. The script already runs as the user, so resolve it at
runtime and delete the evaluation read:

```sh
test -s "${XDG_DATA_HOME:-$HOME/.local/share}/atuin/session"
```

That fix is worth doing on its own; it removes one of the five read-back sites with no design
decision.

## Migration path

Each step is independently testable.

1. **Port `userDefaults.persist` to universal** from den. No behaviour change until step 2.
2. **Move the seven base paths** of `disks/default.nix:575-616` from `sharedModules` writes to
   `userDefaults.persist`. Compare `preservation.preserveAt` before and after: the user entries must
   be identical.
3. **Default `cfg.users`** from `config.users.users` and iterate `cfg.users` in
   `preserveAt.users` and in the service-ordering block. Drop the two `home-manager.users` reads at
   `config.nix:135-146`.
4. **Add the base directory set** (the four XDG dirs, the media dirs, `.ssh`, `.gnupg`) to the
   machine layer. This is a **superset** of today's persisted paths for every host, by construction.
5. **Delete the `kdn.apps` persist write** and the per-program writes inside XDG.
6. **Move the outside-XDG writes** to their module's host branch, one file per commit.
7. **Delete the `hmConfig.kdn.disks.persist` read** at `config.nix:43` and the
   `kdn.disks.enable` forward at `config.nix:15`.
8. **Atuin**: runtime path, delete the read at `default.nix:268`.
9. **Den**: the same steps in `modules/den/aspects/disks.nix` and the aspect writers. Den starts
   closer: `userDefaults.persist` exists and the base paths are already there.

After steps 7 and 8, `nix eval` of a host with `home-manager.users = lib.mkForce { }` succeeds. That
is the proof that the persistence loop is gone, and the first real measurement of the parent side.

## Proof and acceptance

1. **The loop is gone.** `oams` evaluates with `home-manager.users = lib.mkForce { }`, without
   emptying `kdn.programs.atuin.autologinUsers`. Today it dies at `atuin:268`; after the change it
   must return a `drvPath`.
2. **Coverage, not equality.** Dump `config.preservation.preserveAt` as JSON before and after, per
   host. Every file and directory persisted before must be covered by a persisted directory after;
   R1 is coarser, so the old exact paths disappear. Extra coverage is the accepted cost of R1 and
   belongs in the note, not in a surprise.
3. **The boot order holds.** `preservation.target` still precedes any Home Manager activation that
   remains. In the split end state the parent has no HM service, so the check moves to the wrapper.
4. **No unrelated closure change.** The system closure changes because it now holds more tmpfiles
   and mount units. Compare the `preservation.preserveAt` and `systemd.tmpfiles` option values, and
   use a closure comparison for the rest — never `drvPath` on a universal host
   ([definition.md](definition.md) § "The `drvPath` caveat").
5. **`den-eval-instantiate` does not rise.** The change touches the instantiate path only through
   the disks aspect; measure with `nix build --no-eval-cache -L`.

## Open decisions

- **Does `.cache` persist at all?** `usr/cache` takes no snapshots; persisting it saves a warm cache
  and grows the disk. A host-level switch is cheap: leave it out of the base set and declare it per
  host.
- **Exclusions under `.config`.** Whole-directory persistence brings generated files. A short
  exclude list is possible, but it reintroduces per-path data. Start with none.
- **A user who overrides `XDG_DATA_HOME` or `xdg.userDirs`.** R1 assumes the defaults. An override
  needs a host entry; the base set must not silently persist the wrong directory.
- **`root`.** Not a normal user, but it has a Home Manager config on the hosts where root needs one.
- **Darwin.** `kdn.disks` is NixOS-only (`disks/default.nix:120` adds `config.nix` for `nixos`
  alone), so this design has no Darwin side.

## Related

- [hm-split.md](hm-split.md) — the parent/Home Manager split and the full dependency inventory.
- [design.md](design.md) § 2 — the counters and parity rules that a measurement must follow.
