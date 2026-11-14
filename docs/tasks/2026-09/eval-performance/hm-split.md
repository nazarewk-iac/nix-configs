---
type: Research
description: The idea of evaluating a host's parent system and its Home Manager users as separate outputs, the two-way dependency inventory that blocks it today, and the deploy tooling such a split needs.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T09:20:00+01:00
---

# Parent and Home Manager as separate evaluations

A host evaluation today forces the whole Home Manager graph. The reverse also holds: Home Manager
reads the parent configuration. This note records the idea of breaking that in two — one parent
output and one output per Home Manager user — plus the tooling that would deploy both together by
default. It also records why a naive split cannot be measured yet, and the dependency inventory that
must shrink first.

**No number in this note is a measurement of the split.** The split costs one number that this repo
cannot produce today. § "The measurement that would work" states the protocol; § "The inventory" is
the starting point that must come first.

## The proposal

Evaluate two independent outputs per host:

| Output                                   | Holds                                   | Forced by                                |
| ---------------------------------------- | --------------------------------------- | ---------------------------------------- |
| `nixosConfigurations.<host>` / `darwin…` | users, groups, mounts, services, kernel | `nixos-rebuild switch`, `darwin-rebuild` |
| `homeConfigurations."<host>.<user>"`     | that user's Home Manager generation     | `home-manager switch`, one process each  |

A wrapper deploys both by default, in order, with one lock, one log and one exit code. Flags deploy
one side only: `--parent-only`, `--home-only [user…]`, `--build-only`. The split buys three things:

1. A parent evaluation stops forcing the Home Manager module graph and its packages.
2. One Home Manager process per user reaches other cores. Lix has no `eval-cores`
   ([design.md](design.md) § preamble), so process parallelism is the only route.
3. An edit to one side leaves the other side's evaluation cache entry valid.

The parent figure in [definition.md](definition.md) is the target. The split is one candidate for
exit criterion 1, not a decision.

## Why a naive split does not evaluate today

The first attempt evaluated `oams` twice from one pinned revision. The "no Home Manager" side forced
`home-manager.users = { }` and the run died at
`modules/universal/programs/atuin/default.nix:268`:

```text
error: attribute 'kdn' missing
at …/modules/universal/programs/atuin/default.nix:268:58:
    hmUser = config.home-manager.users."${username}";
```

That is one of several parent-side reads of Home Manager values. The dependency runs both ways, so
neither side evaluates without the other:

- The parent reads `home-manager.users.<user>` to build its own units and disk layout.
- Home Manager reads `osConfig`, `darwinConfig` and `kdnConfig.parent` to build the user config.

A real split replaces both directions with plain data. It is not a flake-output edit.

## The inventory

Every count below is reproducible with the command next to it. Scope:
`modules/universal`, `modules/den`, `modules/slots`, `hosts`, `hosts-den`, `lib`.

### 1. Parent → Home Manager: the parent writes user config

| Edge                                             | Count                   | Command                                                          | What it does                                                                                                                                               |
| ------------------------------------------------ | ----------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `kdnConfig.util.ifHMParent`                      | **60 uses, 60 files**   | `grep -rn ifHMParent --include=*.nix modules/universal \| wc -l` | A parent branch forwards its settings into `home-manager.users.*`. Without the parent there is no forward.                                                 |
| `home-manager.sharedModules`                     | **138 uses, 113 files** | `grep -rn home-manager.sharedModules --include=*.nix … \| wc -l` | The broadest bridge: every module can inject any Home Manager module into every user.                                                                      |
| `home-manager.users.<name>`                      | **31 uses, 20 files**   | `grep -rn home-manager.users --include=*.nix … \| wc -l`         | Direct writes, e.g. `modules/universal/profile/user/kdn/default.nix:180`, `hosts/oams/default.nix:148`. A few are reads and comments; § 2 lists the reads. |
| `home-manager.extraSpecialArgs`                  | 1                       | `grep -rn extraSpecialArgs --include=*.nix …`                    | `modules/universal/default.nix:94` passes the nested meta-module arguments into every user.                                                                |
| `home-manager.useGlobalPkgs` / `useUserPackages` | 3 sites                 | see below                                                        | `modules/universal/default.nix:97-98` turns both on; `modules/den-pkgs/pin-module.nix:27-28` forces both on for a pinned host.                             |
| `lib/slots` `renderUsers`                        | 1 renderer              | `lib/slots/default.nix:45-47`                                    | A slot writes `users.<name>` and the host hands the result to `home-manager.users.<name>`.                                                                 |

The forward direction is the bulk of the work: 60 modules and 113 files assume a parent that can
write user config.

### 2. Parent reads Home Manager back: the parent forces the user graph

A read is worse than a write for a split, because it forces Home Manager from the parent
evaluation.

| Site                                               | Reads                                                        | Forced by                                       |
| -------------------------------------------------- | ------------------------------------------------------------ | ----------------------------------------------- |
| `modules/universal/disks/config.nix:71`            | each user's `kdn.disks.persist.<bucket>.{files,directories}` | the `preservation.preserveAt` user entries      |
| `modules/universal/disks/config.nix:135`           | `builtins.attrNames` of `home-manager.users`                 | `kdn.disks.users`                               |
| `modules/universal/disks/config.nix:136-146`       | each user's `home.username`                                  | `systemd.services.home-manager-<user>` ordering |
| `modules/universal/programs/atuin/default.nix:268` | `home-manager.users.<user>.xdg.dataHome`                     | the autologin unit's script text                |
| `modules/den/aspects/disks.nix:73`                 | `config.home-manager.users or { }` and `.kdn.disks.persist`  | persistence, even after the den port            |

The den tree kept this read on purpose. `modules/den/common/persist.nix:17` and
`modules/den/aspects/disks-persist.nix:7` state it: the host reads the user's persist paths back
through `home-manager.users.<name>.kdn.disks.persist`. That is the one edge the den port did not
remove. [design-persistence.md](design-persistence.md) designs its removal: a bucket-level base
policy on the host, so the parent never needs the user's persist lists.

### 3. Home Manager → parent: the user config reads the system config

Home Manager's own NixOS and nix-darwin modules pass the whole parent config to every user as
`osConfig`, and they add `nixosConfig` through `extraSpecialArgs`. The universal tree turns that into
`parentConfig`:

```nix
# modules/universal/default.nix:14-18, and the same block in _hm-bootstrap.nix:12-16
parentConfig = ensure osConfig // ensure darwinConfig;
```

The real forced reads are few and specific. The rest of the 34 `osConfig` occurrences are arguments,
declarations, comments, or dead bindings.

| Site                                                               | Reads                                                                           | Consequence of a standalone user eval                                                                                  |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `modules/universal/_hm-bootstrap.nix:30-45`                        | `parentConfig.home-manager.useGlobalPkgs`, `nixpkgs.config`, `nixpkgs.overlays` | With no parent, the user builds its own nixpkgs. A full extra instantiation, unless the caller passes the host `pkgs`. |
| `modules/universal/programs/firefox/default.nix:138-139`           | `osConfig.programs.firefox.policies` and `.languagePacks`                       | The standalone branch silently writes no policy and no language pack.                                                  |
| `modules/universal/programs/thunderbird/default.nix:58`            | `osConfig.programs.thunderbird.policies`                                        | Same silent drop.                                                                                                      |
| `modules/universal/virtualisation/containers/default.nix:19,202`   | `osConfig.boot.kernelPackages.oci-seccomp-bpf-hook`                             | The seccomp hook drops out; `hasOciHook` is false.                                                                     |
| `modules/universal/_stylix.nix:26,53`                              | `kdnConfig.parent == null`                                                      | A parentless user takes the **other** stylix branch: Home Manager integration instead of the host's.                   |
| `modules/universal/desktop/sway/home-manager/kanshi/default.nix:2` | nothing — the argument is unused                                                | Dead. Remove it.                                                                                                       |
| `modules/universal/desktop/sway/home-manager/swaylock.nix:12`      | nothing — `sysCfg` is bound and never used                                      | Dead. Remove it.                                                                                                       |
| `modules/universal/desktop/sway/home-manager/default.nix:32`       | nothing — same dead `sysCfg`                                                    | Dead. Remove it.                                                                                                       |
| `modules/universal/profile/user/bn/default.nix:159`                | a **user record**, not the OS config                                            | A naming trap: the option is called `osConfig` inside a user scope.                                                    |
| `modules/universal/profile/user/sn/default.nix:148`                | the same user record                                                            | Same trap.                                                                                                             |

So the parent → user direction is one real bridge (`_hm-bootstrap`), three content reads, one branch
selector (`stylix`), and three dead bindings. This is much smaller than the 113-file direction in § 1.

### 4. Home Manager's own system contract

Even after the repo's own edges are gone, Home Manager's NixOS module reads the parent and the parent
reads Home Manager. These are upstream, not repo code
(`home-manager/nixos/default.nix` and `home-manager/nixos/common.nix`):

| Upstream read                                                 | Line                       | Meaning for a split                                                                                     |
| ------------------------------------------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------- |
| `usercfg.home.username`, `homeDirectory`, `activationPackage` | `nixos/default.nix:78`     | Builds the `home-manager-<user>` systemd service. Without the service there is no boot-time activation. |
| `usercfg.home.path`                                           | `nixos/common.nix:181`     | With `useUserPackages = true`, puts the user profile in `users.users.<name>.packages`.                  |
| `config.warnings`, `config.assertions`                        | `nixos/common.nix:187,194` | The parent reports and enforces every user's Home Manager assertions.                                   |

The last row is a behaviour change that a split must decide on: a standalone `home-manager switch`
still fails on an assertion, but `nixos-rebuild switch` no longer sees it.

### 5. The den tree already removed most of one direction

The den port is the working precedent, and its rule is written down
(`modules/den/aspects/hm-bootstrap.nix:29-40`): an aspect works in a standalone Home Manager, so it
cannot depend on a parent.

| Ported aspect             | Old read                                             | Den replacement                                                       |
| ------------------------- | ---------------------------------------------------- | --------------------------------------------------------------------- |
| `hm-bootstrap`            | `osConfig`/`darwinConfig` nixpkgs bridge             | `home-manager.useGlobalPkgs = true` on the host, one line, no aspect  |
| `program-firefox`         | `osConfig.programs.firefox.{policies,languagePacks}` | The consumer writes the policy into the user's own `programs.firefox` |
| `program-thunderbird`     | `osConfig.programs.thunderbird.policies`             | The same, into the user's `programs.thunderbird`                      |
| `program-atuin`           | `home-manager.users.<user>.xdg.dataHome`             | `runtimeDir` carries the value; the user config knows its own uid     |
| `disks` / `disks-persist` | `home-manager.users` write and read-back             | **Still present.** The persistence model reads the user's paths back. |

`flake.denHomeConfigurations` and `checks/den-mvp/home/default.nix` already evaluate standalone Home
Manager configurations with no den entity and no host. So the den tree already has the output shape
that this proposal needs. What it does not have is a real host whose users are wired that way.

## What each edge must become

| Edge class                                  | Replacement                                                                                     | Precedent                                    |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------- | -------------------------------------------- |
| `ifHMParent` forward (60)                   | A user-scope aspect owns the setting; the parent keeps only host-level config                   | `modules/den/aspects/hm-bootstrap.nix`       |
| `sharedModules` injection (138 / 113 files) | A declared option on the host, read by the user entity — or move the whole module to user scope | `program-firefox` policy option              |
| Parent read-back (5)                        | Explicit data: `kdn.disks.users.<name>`, a `runtimeDir` option, or a per-user data file         | `program-atuin` `runtimeDir`                 |
| `osConfig` content read (3)                 | A defaulted option on the user side; the consumer sets it                                       | `program-firefox`, `program-thunderbird`     |
| `osConfig` pkgs bridge (1)                  | Pass the host's `pkgs` into `homeManagerConfiguration`, or `useGlobalPkgs = true`               | `modules/den/aspects/hm-bootstrap.nix:39-40` |
| `kdnConfig.parent == null` (stylix)         | Make the choice an explicit option, not a structural guess                                      | `modules/den/aspects/stylix.nix`             |

## The deploy tooling

The tooling is the small part, and it is worth designing now because the output shape depends on it.

### Shape

```bash
./host-switch.sh oams                     # parent, then every user: the default
./host-switch.sh oams --parent-only       # one side, on demand
./host-switch.sh oams --home-only kdn     # one user, on demand
./host-switch.sh oams --build-only        # evaluate and build both, activate neither
./host-switch.sh oams --dry-run           # print the two attribute sets and the user list
```

- **Discovery.** `hosts/<name>/meta.json` gives `system` and `moduleType`; the user list comes from
  one attribute (`homeConfigurations."<host>"` with `attrsOf`), never from a second source.
- **Order.** Parent first: it owns users, groups, mounts and secrets. Home Manager second.
- **Privilege.** Parent needs `sudo`. Each Home Manager switch runs as its user, so the wrapper
  either runs as that user (`sudo -u`) or tells the user to run it.
- **Remote.** The existing wrappers already handle `--target-host` and a builder host
  (`nixos-rebuild.sh:112-116`). The Home Manager side has no remote switch, so the wrapper must SSH
  per user or refuse with a clear message.
- **One lock and one log.** Two builders can otherwise race on `flake.lock`. The existing wrappers
  hash and restore nothing; the split wrapper should take the same lock guard as
  `hack/eval-profile.sh:55-72`.
- **Exit code.** One exit code for the pair. A failed Home Manager user must not look like a
  successful switch.

### What it must not do

- It must not let the user side re-import nixpkgs. That turns one nixpkgs instantiation into two and
  cancels most of the win. Pass the host `pkgs`, or set `useGlobalPkgs`.
- It must not activate Home Manager before the parent's users, groups and mounts exist.
- It must not hide a Home Manager assertion behind a successful parent switch.

## Hazards and behaviour changes

1. **Assertions and warnings move out of `nixos-rebuild`.** A bad user config no longer stops a
   system switch. The wrapper must run the user evaluation, or the policy must accept the change.
2. **Two generations per user and one per system.** A rollback is no longer atomic. A boot entry can
   pair an old system with a new Home Manager generation.
3. **`useUserPackages` semantics.** Today the user profile is a package of `users.users.<name>`, so
   the system closure holds it. After a split the profile lives only in the Home Manager generation.
4. **Silent standalone branches.** Firefox policies, Thunderbird policies, the containers seccomp
   hook, and stylix all take a different branch with no parent. Each is a behaviour change, not a
   crash.
5. **The persistence model.** The per-user preserve lists, `kdn.disks.users`, and the
   `home-manager-<user>` ordering read from the parent. [design-persistence.md](design-persistence.md)
   designs the inversion to explicit host data.
6. **Darwin.** Home Manager as a module rides `darwin-rebuild`'s activation. A standalone
   `home-manager switch` on darwin activates through its own launchd path. The two paths are not the
   same code.
7. **`drvPath` churn.** `kdnConfig.self` reaches every universal host, so every repo edit changes
   both new outputs. The caveat in [definition.md](definition.md) still applies; a split does not
   remove it, it only halves the graph behind each path.
8. **Cache politeness.** Two outputs evaluated in one process share the nixpkgs instance. Two
   processes do not, unless the pinned `pkgs` from
   [../../2026-11/pinned-pkgs-single-instantiation/definition.md](../../2026-11/pinned-pkgs-single-instantiation/definition.md)
   is passed in.

## The measurement that would work

`checks/universal-guards.nix` and `checks/standalone.nix` already build stub parents
(`osStub`, `hmMeta`, `hostMeta`) and standalone Home Manager evaluations. Reuse that harness; do not
`mkForce` a real host, which is what failed here.

Three numbers, one pinned revision, one warm store, one evaluator:

| #   | Attribute                                                                        | What it proves           |
| --- | -------------------------------------------------------------------------------- | ------------------------ |
| A   | the real host toplevel `drvPath`                                                 | the baseline             |
| B   | the same host with the HM users and the five read-backs stubbed                  | what the parent saves    |
| C   | one real user's standalone Home Manager `activationPackage` with the same `pkgs` | what the user side costs |

Acceptance for the idea:

1. **B is measurably below A** — the parent win is real.
2. **B + C ≤ A × 1.1** with one shared `pkgs` — the split moves work, and does not add it.
3. The `nrFunctionCalls` and `cpuTime` counters agree with the wall-clock direction, as
   [design.md](design.md) § 2 requires.

Until B and C exist, the split has no number and the task keeps its current levers.

## Where to start

Do not build the wrapper first. Build the inventory down to zero in the den tree, because that tree
already holds the rule and the output shape:

1. **Finish the den user route.** Wire one real `hosts-den` host to a den user entity and one
   `denHomeConfigurations` entry. That is the first end-to-end pair, with no universal edits.
2. **Invert the persistence read-back.** It is the only leftover parent → user read in den; the
   design is in [design-persistence.md](design-persistence.md).
3. **Prototype the wrapper** against that one host and one user. The wrapper is about 150 lines and
   reuses the remote and builder handling of `nixos-rebuild.sh`.
4. **Measure B and C** with the stub harness, then decide whether the universal tree pays for the
   60 + 138 + 31 edits that a split needs there.

The universal tree's cost is the reason to start in den: 60 `ifHMParent` sites, 113
`sharedModules` files and 20 files of direct user writes are a rewrite, not a switch.

## Regenerating the counts

```bash
cd <repo>
grep -rn ifHMParent --include=*.nix modules/universal | wc -l
grep -rn home-manager.sharedModules --include=*.nix modules/universal modules/den modules/slots hosts hosts-den lib | wc -l
grep -rln home-manager.sharedModules --include=*.nix modules/universal modules/den modules/slots hosts hosts-den lib | wc -l
grep -rn home-manager.users --include=*.nix modules/universal modules/den modules/slots hosts hosts-den lib | wc -l
grep -rn osConfig --include=*.nix modules/universal modules/den hosts hosts-den lib | wc -l
```
