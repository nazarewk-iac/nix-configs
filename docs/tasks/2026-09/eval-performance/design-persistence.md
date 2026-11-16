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
| `modules/den/aspects/disks.nix:73,749`       | `config.home-manager.users` and the same persist lists    | the persist-list read                        |
| `modules/den/aspects/disks.nix:836-846`      | the user names and `home.username`                        | `kdn.disks.users` and the service order      |

Two facts make this tractable:

1. **No Home Manager code reads `kdn.disks.persist`.** Every Home Manager occurrence is an
   assignment. The only reader is the parent, at `config.nix:43` and `disks.nix:749`. So the option
   can stop existing in the user scope with no HM consumer to update.
2. **`kdn.disks.enable` has no Home Manager consumer either.** The parent forwards it at
   `config.nix:15`; nothing reads it. Den already dropped that forward
   (`modules/den/aspects/disks.nix:28`).

So the host needs three facts from the user graph: the user names, one path list per bucket, and the
systemd unit names. Two of the three are host data already (`config.users.users`).

## What the persist data looks like today

`preservation.preserveAt.<bucket>.users.<user>` merges **two** layers in universal
(`config.nix:42-45`: the Home Manager lists and `persists.users.<user>`), and **three** in den
(`disks.nix:747-750`, where `userDefaults.persist` joins them):

| Layer                                             | Owner        | Example                                        |
| ------------------------------------------------- | ------------ | ---------------------------------------------- |
| `kdn.disks.userDefaults.persist` (den only today) | host         | `.cache/nix`, `Downloads`, the four media dirs |
| `hmConfig.kdn.disks.persist.<bucket>`             | **the user** | `.cache/zellij`, `.aws`, `.gnupg`              |
| `kdn.disks.persist.<bucket>.users.<user>`         | host         | a per-user path a host names directly          |

The `kdn.apps` registry is the largest writer: each app declares `dirs` and `files` per bucket, and
`modules/universal/apps/default.nix:111-160` writes all twelve lists into `kdn.disks.persist` from
the `ifHM` branch. `modules/den/aspects/apps.nix` publishes the same data as
`kdn.apps-persist` and asks the consumer to wire it.

**The key observation.** `modules/universal/apps/default.nix:57-71` prefixes a list with a fixed
directory, and `:22-30` **strips** a leading `/` instead of honouring it:

| Bucket         | Prefix         |
| -------------- | -------------- |
| `usr/cache`    | `.cache`       |
| `usr/config`   | `.config`      |
| `usr/data`     | `.local/share` |
| `usr/state`    | `.local/state` |
| `disposable`   | none (`""`)    |
| `reproducible` | none (`""`)    |

So every app entry is relative to `$HOME`, and the four `usr/*` buckets sit inside the four XDG
directories — **except an entry that starts with `/`**. That slash is stripped, so the entry lands
at the home root. The real ones:

| Entry                       | Module                              |
| --------------------------- | ----------------------------------- |
| `/.thunderbird`             | `programs/thunderbird:43`           |
| `/.mozilla/firefox`         | `programs/firefox:86`               |
| `/.omp`, `/.pi`             | `development/llm/{omp,pi}:27`       |
| `/.claude`, `/.claude.json` | `development/llm/claude-code:25-26` |
| `/.wine`                    | `emulation/wine:42`                 |

`disposable` is rolled back to `@empty` on every boot (`config.nix:150-205`), so a home path there
is equivalent to ephemeral. `reproducible` takes no snapshots and nearly every app declares it
empty; the one non-empty entry (`nextcloud-client`, `Nextcloud`) is a home-root path and joins the
exception list.

That is the design opening: make the four XDG directories the unit of persistence, and the bulk of
the app output — every XDG-prefixed list — disappears without a migration. The leading-slash entries
become part of the exception list.

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

Every base entry is an attrset, so it can carry a mode. The current default is `homeDirMode` =
`0750`; `.gnupg` must stay `0700`.

| Base entry                                                | Bucket                                 | Notes                                                        |
| --------------------------------------------------------- | -------------------------------------- | ------------------------------------------------------------ |
| `.config`                                                 | `usr/config`                           | covers the XDG-prefixed `dirs.config`/`files.config` entries |
| `.local/share`                                            | `usr/data`                             | covers the XDG-prefixed `dirs.data`/`files.data` entries     |
| `.local/state`                                            | `usr/state`                            | covers the XDG-prefixed `dirs.state`/`files.state` entries   |
| `.cache`                                                  | `usr/cache`                            | covers the XDG-prefixed `dirs.cache`/`files.cache` entries   |
| `Documents`, `Desktop`, `Pictures`, `Videos`, `Downloads` | `usr/data`, `Downloads` in `usr/cache` | the media dirs `disks/default.nix:604-616` writes today      |
| `.ssh`, `.gnupg`                                          | `usr/data`                             | `.gnupg` keeps `{ mode = "0700"; }`; see `gnupg:93-98`       |

After that set, the XDG-prefixed part of the `kdn.apps` output and about 90 % of the per-program
writes become unnecessary. The survivors are the paths outside the four XDG directories:

| Survivor                                                                | Where it lives today                                | Replacement                    |
| ----------------------------------------------------------------------- | --------------------------------------------------- | ------------------------------ |
| `.aws`                                                                  | `development/cloud/aws:16`                          | host branch of the same module |
| `.java/.userPrefs/...`                                                  | `development/jetbrains:158-161`                     | host branch of the same module |
| `.thunderbird`, `.mozilla/firefox`                                      | `thunderbird:43`, `firefox:86`                      | host branch of the same module |
| `.omp`, `.pi`, `.claude`, `.claude.json`, `.wine`                       | `omp:27`, `pi:27`, `claude-code:25-26`, `wine:42`   | host branch of the same module |
| shell histories (`.bash_history`, `.zsh_history`, `.python_history`, …) | `profile/machine/baseline:120-125`                  | base entry or host branch      |
| `dev`, `Games`                                                          | `profile/user/kdn:296`, `profile/machine/gaming:84` | host branch or per-user entry  |
| `Nextcloud`                                                             | `nextcloud-client:41` (`usr/reproducible`)          | host branch                    |

That table is a scope estimate, not a census. Regenerate it from
`config.preservation.preserveAt` on a real host before deleting a write (see "Proof and acceptance").

**Re-bucketing is the real cost.** Some modules deliberately put a path in a _different_ bucket than
its XDG prefix. `profile/machine/gaming:86-95` sends `.local/share/Steam/steamapps`,
`.local/share/lutris/runtime` and `.local/share/bottles/{runners,temp,dxvk}` to `usr/cache`, while
`.local/share/Steam`, `lutris` and `bottles` are in `usr/data`. Whole-`.local/share` persistence puts
all of it in `usr/data`, which takes snapshots (`disks/default.nix:468-471`). A gaming host needs an
explicit override or must accept the snapshot growth. The same mismatch exists at
`hw/audio:57` (wireplumber in `usr/config`), `nwg-shell:92` (`.cache/nwg-pin-cache` in `usr/config`)
and `baseline:120` (a `usr/state` file under `.local/share`).

Cost: more data persists. `.config` now persists whole, including generated files that used to be
left out. That is the normal impermanence trade-off; the four buckets still separate the snapshotted
halves (`config`, `data`) from the disposable ones (`cache`, `state`). Three consequences need a
decision before it lands:

- **Secrets under `.config`.** The rosec default age identity is
  `~/.config/sops/age/keys.txt` (`modules/universal/services/rosec/default.nix:199`), and provider
  tokens live under `.config` too. Whole-`.config` persistence makes them persistent _and_
  snapshotted. Audit the tree before "start with no exclusions" becomes the policy.
- **Home Manager generations become gc roots.** `environment.profiles` includes
  `$HOME/.local/state/nix/profile` (`nixpkgs users-groups.nix:979`). Persisting `.local/state` keeps
  every generation rooted; pair it with a `nix-collect-garbage --delete-older-than` policy.
- **`hmbackup` files accumulate.** `modules/universal/default.nix:96` sets
  `backupFileExtension = "hmbackup"`. In a tmpfs home they vanish per boot; under whole-`.config`
  persistence they accumulate forever. Add a cleanup rule.

The switch deserves one reboot. On a live system the old per-file mounts can outlive the switch and
become unreachable under the new directory mount. A `nixos-rebuild boot` plus a reboot removes the
doubt; then check that `findmnt` shows one mount per base directory.

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

`cfg.users` stops defaulting from `home-manager.users`. Do **not** default it from all of
`config.users.users`: `users.users.<name>.home` defaults to `/var/empty`
(`nixpkgs users-groups.nix:225-228`), and every system user that omits a home shares it.
`preservation` emits one tmpfiles `d` rule per user directory with `user = <name>`
(`preservation lib.nix:232`), so two system users with the same `/var/empty` collide on one key
with different values — the `conflicting definition values` failure already documented at
`config.nix:220-239`. Filter to `u.isNormalUser` and exclude `home == "/var/empty"`, then add
explicit entries for `root` and any service user that needs a home.

`root` is not optional. `modules/universal/services/nextcloud-client-nixos/default.nix:50` writes
`kdn.disks.persist."usr/reproducible".users.root.directories`, and `config.nix:259` reads
`cfg.users."${username}"` with no fallback. A filter that drops root throws `attribute 'root'
missing` on every host with that service. Its default `homeLocation` is `disposable`
(`disks/default.nix:472`), so give it a chosen bucket.

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

| Kind                                                 | Count (approx.)             | Action                                                                                        |
| ---------------------------------------------------- | --------------------------- | --------------------------------------------------------------------------------------------- |
| `kdn.apps` → `kdn.disks.persist`                     | 12 lists                    | Delete the XDG-prefixed ones; move the leading-slash entries to host branches                 |
| Per-program `ifHM`/`sharedModules` writes inside XDG | ≈40 universal, ≈20 den      | Delete                                                                                        |
| Per-program writes outside XDG                       | ≈10 universal, a few in den | Move to the module's host branch                                                              |
| `disks/default.nix:575-616` sharedModules base       | 7 paths                     | Move to `userDefaults.persist`                                                                |
| `disks/config.nix:15` `kdn.disks.enable` forward     | 1                           | Delete                                                                                        |
| den aspect writes (`profile-*`, `zellij`, `apps`, …) | part of the ≈20 above       | The same, per aspect; den's gnupg already goes through the app registry (`program-gnupg:223`) |

The per-program figures are a scope estimate. Count them with
`grep -rn 'kdn.disks.persist' --include=*.nix modules/universal modules/den` and classify each hit by
its enclosing `ifHM`, `home-manager.sharedModules` or den `homeManager` target.

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

That fix is worth doing on its own; it removes one of the seven read-back sites with no design
decision.

## Migration path

Each step is independently testable.

1. **Port `userDefaults.persist` to universal** from den. No behaviour change until step 2.
2. **Move the seven base paths** of `disks/default.nix:575-616` from `sharedModules` writes to
   `userDefaults.persist`. Compare `preservation.preserveAt` before and after: the user entries must
   be identical.
3. **Default `cfg.users`** from `config.users.users` filtered to `u.isNormalUser` with a real home,
   plus an explicit `root`, and iterate `cfg.users` in `preserveAt.users` and in the
   service-ordering block. Drop the two `home-manager.users` reads at `config.nix:135-146`.
4. **Add the base directory set** (the four XDG dirs, the media dirs, `.ssh`, `.gnupg`) to the
   machine layer. This is a **superset** of today's persisted paths for every host, by construction.
5. **Delete the `kdn.apps` persist write** and the per-program writes inside XDG.
6. **Move the outside-XDG writes** to their module's host branch, one file per commit.
7. **Delete the `hmConfig.kdn.disks.persist` read** at `config.nix:43` and the
   `kdn.disks.enable` forward at `config.nix:15`.
8. **Atuin**: runtime path, delete the read at `default.nix:268`.
9. **Den**: the same steps in `modules/den/aspects/disks.nix` and the aspect writers. Den starts
   closer: `userDefaults.persist` exists (`:273`) and the base paths are already there. Remove
   `hmUsers` from the merge (`:747-750`), from `kdn.disks.users` (`:836`) and from the service
   ordering (`:837-846`).
10. **Update the checks.** `checks/universal-guards.nix:422-430` and the den assertions
    (`checks/den-mvp/assertions/disks-fs.nix:450-471`, `desktop-leaves.nix:770,791`) assert the
    app→persist mapping. Steps 5, 6 and 9 fail them until they are rewritten to the host-side data.

After steps 7 and 8, `nix eval` of a host with `home-manager.users = lib.mkForce { }` succeeds. That
is the proof that the persistence loop is gone, and the first real measurement of the parent side.

## Proof and acceptance

1. **The loop is gone.** On `etra` (a host with `kdn.disks.enable = true`,
   `hosts/etra/default.nix:178`), `nix eval` with `home-manager.users = lib.mkForce { }` and without
   emptying `kdn.programs.atuin.autologinUsers` must return a `drvPath`. Today it dies at
   `atuin:268`. Do not use `oams` for this proof: it sets `kdn.fs.disko.luks-zfs.enable = true`
   (`hosts/oams/default.nix:159`), which is mutually exclusive with `kdn.disks.enable` (`:435`), so
   every persistence block is `mkIf cfg.enable` and the run would prove only the atuin read.
2. **Coverage, not equality.** Dump `config.preservation.preserveAt` as JSON before and after, per
   host. Every file and directory persisted before must be covered by a persisted directory after;
   R1 is coarser, so the old exact paths disappear. Extra coverage is the accepted cost of R1 and
   belongs in the note, not in a surprise.
3. **The mounts exist, not just the order.** `preservation.target` still precedes any Home Manager
   activation, and every base mount is checked with `findmnt` and `systemctl is-active` after one
   boot. A failed mount unit leaves the target reachable, so the ordering alone proves nothing.
4. **An explicit exit-criterion amendment.** `definition.md` says out of scope "a change that alters
   any host's built output", and exit criterion 3 says no closure may change. R1 changes it by
   design: more tmpfiles and mount units. Record the amendment to criterion 3 in `definition.md`
   before the change lands, and compare the `preservation.preserveAt` and `systemd.tmpfiles` option
   values plus the rest of the closure — never `drvPath` on a universal host
   ([definition.md](definition.md) § "The `drvPath` caveat").
5. **`den-eval-instantiate` does not rise.** The change touches the instantiate path only through
   the disks aspect; measure with `nix build --no-eval-cache -L`.

## Open decisions

- **Does `.cache` persist at all?** `usr/cache` takes no snapshots; persisting it saves a warm cache
  and grows the disk. A host-level switch is cheap: leave it out of the base set and declare it per
  host.
- **Exclusions under `.config`.** Whole-directory persistence brings generated files and the
  secrets named above. A short exclude list is possible, but it reintroduces per-path data. "Start
  with none" is safe only after the secrets audit.
- **A user who overrides `XDG_DATA_HOME` or `xdg.userDirs`.** R1 assumes the defaults. The media
  list hard-codes `Documents`/`Desktop`/… while `profile/machine/baseline:111-113` sets
  `xdg.userDirs.createDirectories = false`, so a renamed directory is real. A host entry would
  duplicate user data and recreate the coupling; prefer one `kdn.xdg.*` data value read by both
  sides, or state that custom XDG dirs are unsupported under R1.
- **Home Manager generations as gc roots.** Persisting `.local/state` keeps every HM generation in
  `environment.profiles` (`nixpkgs users-groups.nix:979`). Decide the retention rule with the
  change, not after the first fully rooted store.
- **`root`.** Required by `nextcloud-client-nixos:50`; decide its `homeLocation`, not whether it
  exists.
- **Darwin.** The `kdn.disks` option tree is loaded in every class; only the effect half is gated to
  `nixos` (`disks/default.nix:120` adds `config.nix` for `nixos` alone). So this design has no Darwin
  side, and a Darwin Home Manager user may still write `kdn.disks.persist` harmlessly.

## Related

- [hm-split.md](hm-split.md) — the parent/Home Manager split and the full dependency inventory.
- [design.md](design.md) § 2 — the counters and parity rules that a measurement must follow.
