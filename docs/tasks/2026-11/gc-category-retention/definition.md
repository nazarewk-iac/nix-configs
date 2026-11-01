---
type: Task
description: Make the store GC keep the newest build of each CLASS of thing (per-NixOS/darwin host, per-repo devenv shell, per-package one-off) and drop the rest by a short configurable age, using angrr root classes plus an explicit category gcroot for builds that have none.
status: open
authored_by: agent
timestamp: 2026-11-01T16:30:00+01:00
---

# Store GC that keeps the last build per class

## The request

Free store space by keeping only the **newest** build of each kind of thing and deleting the
rest:

| Kind | Keep |
|---|---|
| a NixOS toplevel (with Home Manager, containers, …) | per host: the newest |
| a `darwinConfigurations` toplevel | per host: the newest |
| a `devenv` shell | per repository: the newest |
| a one-off `nix build .#foo` | per package name: the newest, or delete by age |
| everything unclassified | delete older than ~1 h (configurable) |

It should discover the classes itself, present the plan, then delete.

## What already exists in this repo

`angrr` is the GC-root retention engine, and it is **already** the mechanism for this. It deletes
**auto GC roots** by policy, and it already supports exactly the "class keeps N newest and/or a
period" shape:

* `temporary-root-policies.<name> = { path-regex; period; }` — a class by path pattern.
* `profile-policies.<name> = { profile-paths; keep-since; keep-latest-n; }` — a profile class that
  keeps the newest N and/or the last period.

Already declared in `modules/den/aspects/profile-baseline.nix`: `direnv` (7d), `result` (5d),
`devenv` (30d), `system` (14d, keep 5, keep-booted, keep-current), `user` (1d, keep 1).

So the gap is **not** the engine. It is three things:

1. The **periods are long** (30d, 14d) and the request wants ~1 h configurable.
2. There is **no class for a NixOS/darwin toplevel or a per-package one-off**; those are not
   auto roots, so no policy can see them.
3. angrr reads the **symlink target mtime**, and a NixOS toplevel is a profile, not a temporary
   root, so a "newest per host" rule for it needs the profile-policy route.

The sibling task [../../2026-09/angrr-retention/](../../2026-09/angrr-retention/definition.md)
covers starting the timer and the `.devenv` class. This task builds on it; it does not repeat it.

## The two facts that constrain the design

Measured 2026-11-01 on `oams`:

1. **`/nix/store` is mounted `noatime`.**
   `/nix/store rw,nodev,noatime,xattr,posixacl,casesensitive` and a second `ro` view.
   So **filesystem atime is frozen** and is not a usable signal on its own. Upstream has an open,
   unfixed request for last-use tracking (`NixOS/nix#7572`); only a Lix patch
   (`lastReferencedTime` over the daemon protocol) implements it in the store itself.

   This constrains Layers 1, 2 and 2b to the **birth-time proxy**: `registrationTime` and the
   symlink target mtime, which is what angrr reads. It does **not** constrain Layer 3, which
   observes the open event rather than any filesystem timestamp.
2. **The store carries no class metadata.** Today, on `oams`, the roots are dominated by live
   `nix-daemon` workers: `{temp:<pid>}` roots from four devenv-held workers, ~6 500 each, plus
   `run/current-system`, `run/booted-system`, the Home Manager generations and devenv's
   `.devenv/gc/` links. Nothing says "this path is the pryll toplevel". That fact is only
   knowable **at build time**.

## The design

Four stages, and they are **cumulative, not alternatives**: each one solves a case the previous
cannot, and each ships on its own. Stop wherever the value runs out; nothing here is a choice
between mutually exclusive approaches.

| Stage | Solves | Ships without | Effort |
|---|---|---|---|
| **1** retune angrr classes | the age/keep-N policy for roots that exist (devenv, direnv, result, system, HM) | anything new | small — options only |
| **2** `kdn-nix-keep` category roots | a built-but-not-activated toplevel, and "one per package" | any hook or daemon | small — one script + 3 call sites |
| **2b** post-build hook (enqueue only) | forgetting to call stage 2 | the hook, if you only ever use the wrapper | small — one hook + one worker |
| **3** eBPF probe + SQLite store | true last-*use* instead of birth-time | nothing — the first three already satisfy the request | large, and **gated on measurement** |

**Recommended scope for the first pass: stages 1 and 2.** They are the whole request as stated
(keep newest per class, delete by age) with no new daemon and no kernel code. Stage 2b is worth
adding once stage 2 exists, because it removes the one manual step. Stage 3 is a separate project:
it is the only path to a real LRU, so it is written up here but it must not block 1, 2 and 2b.

The first pass is testable two ways, both verified in this task already: `angrr --config …
validate`, then `angrr --config … run --dry-run -n` (a non-TTY run must pass `--no-prompt`, or it
dies with "failed to prompt"), and `angrr run` needs to run as root for `profile-policies` or it
logs "not owned by the current user" and skips them.

### Layer 1 — retune the existing classes to the requested policy

Change the `period`/`keep-since` of the classes that map onto the request, and add the two
missing classes:

| Class | Route | Policy |
|---|---|---|
| `devenv` | temporary-root | per repo via `path-regex = "/\\.devenv/"`; short period (start `3d`, configurable) so an abandoned project drops fast |
| `result` | temporary-root | `1d` (one-off builds) |
| `system` | profile | already `keep-latest-n = 5`, `14d`; keep as is — this IS "per NixOS host newest plus rollback" |
| **`home-manager`** | profile | **new**: `keep-latest-n = 2`, short period |
| **`nixos-toplevels`** | category gcroot (Layer 2) | newest per host |

The requested "~1 h" belongs on the **one-off** class, not on devenv/system: 1 h for a shell you
entered this morning would reap it immediately. So the configurable knob is
`profile-baseline-gc.oneOffRetention` (default `1d`) and `devenvRetention` (default `3d`).

### Layer 2 — an explicit category gcroot for builds that have no root

A NixOS/darwin toplevel that was **built but not activated** has no root, so no policy can keep
it. The honest fix is to give it one, at build time, under a namespaced directory:

```
/nix/var/nix/gcroots/categories/<class>/<id>   ->  /nix/store/...-nixos-system-<host>
```

`nix-store --add-root --indirect` (or `nix build --out-link`) writes the link; a rebuild replaces
it, so exactly one path per class+id stays live, and `nix-collect-garbage` handles the rest. This
is the *only* way to get "newest build per configuration", because only the builder knows the
class.

Add `kdn-nix-keep` (`packages/kdn-nix/kdn-nix-keep.sh`) with one verb:

```
kdn-nix-keep --class nixos/pryll   /nix/store/...-nixos-system-pryll
kdn-nix-keep --class pkg/hello     /nix/store/...-hello-2.12.3
```

It writes the indirect root atomically (write a temp symlink, then rename) and prints the path it
replaced. `--list` shows every class and its current target. `--prune <class> --older-than 1h`
removes stale links in a class. The flake's `nixos-rebuild`/`darwin-rebuild` app calls it, so an
ordinary build records the class.

Uncategorized one-off builds then have a class of their own (`pkg/<name>`), which satisfies "one
per package", and a build with no class call is simply not rooted — GC reaps it, which is the
requested default.

### Layer 2b — a daemon-wide post-build hook, so categorisation is automatic

Manual `kdn-nix-keep` calls are easy to forget. `post-build-hook` runs after **every** build and
gets `$OUT_PATHS`, `$DRV_PATH`, `$DRV_PATH` and `$OUTPUT_ID`, so it can write the category root
with no caller discipline.

Two rules, both from the manual's own warning that **the hook blocks the build loop and the build
loop exits if the hook fails**:

1. **The hook only enqueues.** It appends one line to a queue file and returns. A separate
   `kdn-nix-gc-categorize` worker drains the queue and runs `nix-store --add-root --indirect`.
   Precedent: `newAM/nix-post-build-hook-queue`. A broken hook must never break `nix build`.
2. **The category must come from the caller, not from the path.** `$OUT_PATHS` is a closure of
   store paths and carries no "pryll". So the rebuild wrapper exports
   `KDN_GC_CLASS=nixos/pryll` (or `darwin/<host>`, `devenv/<repo>`) before invoking the build; the
   hook reads it and falls back to `pkg/<drvName>` for a one-off. This is the *only* way to get the
   class right, because the information exists nowhere else at hook time.

With that, the `pkg/<name>` fallback gives "one per package" for free and an unclassified build
is simply never rooted, so the next GC reaps it — the requested default.

### Layer 3 — true last-use tracking: a thin eBPF observer, a fat userspace daemon

This is the answer to "track when store paths were last accessed", and it is **not blocked by
`noatime`**, because it never reads a filesystem timestamp.

#### The split

The kernel side must be small and cheap; the storage side must not be. So two processes with one
narrow interface:

| Process | Runs where | Does | Must never |
|---|---|---|---|
| **`kdn-nix-atime-probe`** | kernel (BPF program + tiny loader) | update one hash map entry per open | allocate, block, log per event, or exit on a map-full |

| **`kdn-nix-atime-store`** | userspace daemon | drain the map into SQLite, non-synchronously | run in the build path |

#### The interface between them

A **bounded BPF ringbuf** (or a perf event array) carrying only `{hash32, ts}`, plus a userspace
poll loop. That is the "signal the non-eBPF daemon" step: the probe does no I/O, and the daemon
owns every syscall. If the ring fills, the probe **drops** events and bumps a `lost` counter — it
must never stall the traced process or grow without bound.

#### The storage: SQLite, non-synchronous, batched

A single table, one row per store path:

```sql
PRAGMA journal_mode = WAL;        -- writers never block readers
PRAGMA synchronous = NORMAL;      -- batched, survives a crash, not a power cut
CREATE TABLE access (
  hash   TEXT PRIMARY KEY,        -- the first 32 chars of the store basename, unique
  last   INTEGER NOT NULL,        -- unix seconds of the most recent open
  count  INTEGER NOT NULL DEFAULT 0,
  first  INTEGER NOT NULL
);
```

* **Non-synchronous**: `synchronous = NORMAL` plus one transaction per flush window (e.g. every
  30-60 s) rather than one commit per event. Losing the last minute of access data is harmless.
* **Batched upsert**: one `INSERT … ON CONFLICT(hash) DO UPDATE` per drained batch, inside a
  single transaction. `INSERT OR REPLACE` also works but loses `first`.
* **Bounded growth**: the store has ~360k paths today, so the table is small. Add a periodic
  `DELETE FROM access WHERE last < now - 90d` so the file cannot outlive the store's own content.
* **Not in the build path**: the daemon's writes are its own; `nix build` never waits for it.

#### What it buys

Sorting GC candidates by genuine last use instead of birth — the exact gap in `NixOS/nix#7572`
and what only the Lix `lastReferencedTime` patch solves today. angrr takes a score or an
`--older-than` list from this table; the birth-time proxy stops being used once history exists.

#### Rules that make the signal honest

* **Filter out the build users.** Skip opens by `nixbld*` (UID range) and by the daemon's own
  workers, so a build's reads do not count as use. Without this the table says "used" about
  everything.
* **Count what is executed, not only what is opened.** Add `sched:sched_process_exec` so a binary
  you run daily is not "unused" merely because it was executed, not read.
* **A missing row means "no history yet", not "never used".** Seed a new path's `first` at the
  build or substitution time so nothing looks infinitely stale on first run.
* **One store can have many hardlinks.** Record the access against the store path, not the inode,
  so `--optimise` does not merge the history of two unrelated packages.

#### Gate: measure before building

The open volume on a devenv-heavy host may make even the aggregator cost more than it saves.
Measure first, and record the numbers in this task:

1. opens/second under `/nix/store` during a `devenv shell` entry;
2. opens/second during a full `nixos-rebuild build`;
3. ringbuf `lost` count over one hour of normal work;
4. SQLite file size and flush latency after one day.

If (1) or (2) makes the probe's overhead measurable in the traced workload, or (3) is non-zero in
steady state, record that and **do not ship it** — Layers 1, 2 and 2b already satisfy the request.
### Layer 4 — the plan, and a safe first state

Before any of this deletes a file, it must print the plan. angrr already has this: `--dry-run`
prints one verdict per candidate and removes nothing, and `debug` adds a line per skipped root.
Keep `kdn.profile-baseline-gc.dryRun = true` until the plan has been read once on each host.

## Not in scope, and why

* **Filesystem atime as a signal.** Dead on this host (`noatime`, fact 1) and not to be retried.
  This does **not** exclude Layer 3: eBPF observes the **open event itself**, builds its own
  in-memory map and dumps it to disk, so no filesystem timestamp is involved.
* **Replacing angrr.** It does the class-plus-keep-N job already; a second engine would double the
  maintenance for no behaviour.
* **Automatic class discovery by inspecting store paths.** The store holds no such metadata; the
  per-build hook (Layer 2b) is the honest version, and it still needs the caller to state the
  class.

## Measured while writing this (angrr 0.2.7, `oams`, 2026-11-01)

`angrr run` is fully standalone: `--config <file> validate|run`, no daemon and no NixOS module.
Two behaviours the config must respect, both observed:

1. **`run` prompts by default** (`--interactive=once`) and aborts with
   `failed to prompt: not a terminal` when there is no TTY. Automation must pass `-n`/`--no-prompt`.
2. **`profile-policies` are skipped for a non-owner**: it logged
   `ignore profile "/nix/var/nix/profiles/system" in owned only mode, not owned by the current
   user`. The systemd service runs as root so this is fine in production, but a user-level test
   silently tests nothing.

A dry run against this host already produced real verdicts, e.g.
`[devenv] Remove? ".../.devenv/bash-bash" (1month 12days ago)`, and named each skip reason, which
is the stage-4 plan requirement met by angrr's own `--log-level debug`.

## Acceptance

- `nix eval` shows the new classes in `services.angrr.settings` for both trees.
- On `oams`, a full `angrr --dry-run` prints a verdict for every root and names each skipped root.
- After Layer 2, a build of `denConfigurations.pryll` leaves exactly one link under
  `/nix/var/nix/gcroots/categories/nixos/pryll`, and rebuilding replaces it.
- A one-off `nix build` with no class call is collected by the next GC, as the request asks.
- With Layer 2b, an ordinary `nixos-rebuild build` with `KDN_GC_CLASS` set leaves a category root
  without a manual `kdn-nix-keep` call, and a failing hook leaves the build unaffected.
- Layer 3 is gated on a measurement (opens/second, map memory); if the numbers are bad, record
  that and ship without it.
- Free space is recovered in bounded batches; a single run never holds the store for more than a
  few minutes (the bound from `kdn-nix-collect-garbage -c/-s`).
