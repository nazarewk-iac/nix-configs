---
type: Playbook
description: Extends the flake update workflow for repos maintaining a private fork remote.
timestamp: 2026-08-07T00:00:00+02:00
---

# Flake Update — Fork Workflow

> **Agent note:** This file is installed as `.claude/rules/flake-update.fork.md` via the
> `kdn.jj.fork` devenv slot. See also [flake-update.md](flake-update.md) for the base workflow
> and [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for fork-specific jj patterns.
>
> In non-interactive contexts: `jj split`/`jj describe` are safe with `-m` and `-- <files>`.
> `jj new` and `jj rebase` are non-interactive. `upstream@<fork-remote>` is the stable anchor —
> never use bare `upstream` in revsets.

Extends [flake-update.md](flake-update.md) for repos that maintain a private fork remote
alongside the public kdn remote. See [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for the
underlying jj patterns.

---

## Two rules that override everything

1. **NEVER move bookmarks by hand.** Do NOT run `jj bookmark set` for `main` or `upstream`.
   The `jj sync-remotes` command moves both bookmarks for you. It reads the topology through two
   revset aliases and moves each bookmark to the correct tip:
   - `upstream-tip = latest(upstream-chain)` → the `upstream` bookmark target
   - `fork-tip = latest(fork-chain)` → the `main` bookmark target

   Your only job is to build the correct commit topology. The user runs `jj sync-remotes`
   manually to place the bookmarks and push. See `modules/slots/jj/fork/default.nix` for the
   alias definitions.

2. **`@` is a plain empty change on top of the fork merge.** `@` has a single parent — the fork
   merge. `@` never holds content and never sits in the middle of the graph. When
   `nix run '.#update'` writes `flake.lock` into a merge `@`, that state is transient; the first
   step carves the content into a described commit and leaves `@` empty on top of it. Content in
   `@`, or `@` described in the middle of the graph, is a mistake — fix it at once.

   **One exception, after `jj sync-remotes`.** Once you push, the fork merge and the upstream
   update become immutable. To stack new work you then run `jj new fork-tip upstream-tip`, so `@`
   gets both tips as parents. This dual-parent `@` restores the update workflow's starting state
   (`@` on top of `main` and `upstream`) for the next cycle. This is the ONLY place a dual-parent
   `@` is correct. See [step 6](#6-after-jj-sync-remotes-stack-new-work).

---

## Commit structure

After a completed update, the graph looks like this (as `jj log` draws it):

```
@    (empty working copy)                             single parent = fork merge
○    fork merge — "chore(flake): update"              full flake.lock + devenv.lock    ◄ fork-tip → main
├─╮
│ ○  upstream update — "chore(flake): update (public inputs)"  public flake.lock + devenv.lock  ◄ upstream-tip → upstream
◆ │  main@<fork-remote>                               fork parent, full locks
├─╮
◆    upstream@<fork-remote>                            public parent
```

- **upstream update**: public inputs only, in both `flake.lock` and `devenv.lock` (patch file
  changes go here too). Its parent is the public tip.
- **fork merge**: `flake.lock` and `devenv.lock` with all inputs (public + fork-specific). Its
  two parents are the **upstream update** and the fork `main`. So the fork merge sits directly on
  top of the upstream update — that link is the point of the shape.
- **`@`**: a plain empty working copy with a single parent, the fork merge. There is no `@` →
  upstream edge. `@` reaches the upstream update through the fork merge.

The fork merge carries the full locks, so the fork (macOS) build uses them. The upstream update
carries the public-only locks, so the personal NixOS machines build from them in parallel.

Both lock files get the same split. `flake.lock` and `devenv.lock` share the same node schema,
so the fork-specific inputs come out of both the same way. See [devenv.lock](#devenvlock) for the
tool difference.

---

## Quick summary

```bash
# @ is the empty working copy on top of main and upstream
nix run '.#update'
devenv update                       # updates devenv.lock (separate engine from flake.lock)
# patch failed? remove from .flake.patches/config.toml + delete .patch file, then:
#   nix run '.#update' -- g:patches

# 1. carve the update into the fork merge; @ becomes empty on top (never a content merge):
jj split -m 'chore(flake): update' -- flake.lock devenv.lock .flake.patches/
FORK_UPDATE=$(jj log -r @- --no-graph -T 'change_id.short()')

# 2. insert the public-only upstream update between the public tip and the fork merge,
#    in ONE command — BOTH flags: --insert-after adds it, --insert-before re-parents the merge:
jj new --insert-after upstream-tip --insert-before fork-tip -m 'chore(flake): update (public inputs)'
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- "$FORK_UPDATE"   # flake.lock only
# devenv.lock: flake-lock-merge cannot write it (see below). Strip fork nodes with jq:
STRIP=$(comm -23 \
  <(jj file show -r "$FORK_UPDATE" flake.lock | jq -r '.nodes|keys[]|select(test("^brew-tap--"))' | sort) \
  <(jj file show -r @               flake.lock | jq -r '.nodes|keys[]|select(test("^brew-tap--"))' | sort) \
  | jq -R . | jq -sc .)
jj file show -r "$FORK_UPDATE" devenv.lock | jq --argjson strip "$STRIP" '
  .nodes |= with_entries(select(.key as $k | ($strip|index($k))|not))
  | .nodes |= map_values(if .inputs then .inputs |= with_entries(select((.value|tostring) as $t|($strip|index($t))|not)) else . end)
' | jq -j '.' > devenv.lock          # jq -j = no trailing newline, matches native devenv.lock

# 3. park a fresh empty working copy on top of the fork merge (single parent):
jj new fork-tip

# 4. test builds (see Testing). NEVER run `jj bookmark set` — `jj sync-remotes` does that.
```

---

## Step-by-step

### 1. Run the update

With `@` on top of `main` and `upstream`, run:

```bash
nix run '.#update'
devenv update
```

`nix run '.#update'` updates all flake inputs and applies patches. `devenv update` updates
`devenv.lock`, which has a separate resolver (see [devenv.lock](#devenvlock)). The result lands
in `@`, which has both `main` and `upstream` as parents. So `@` is now a content-holding merge.
This state is transient. Step 2 fixes it.

If a patch fails to apply, remove it from `.flake.patches/config.toml` and delete the `.patch`
file, then re-run patches only:

```bash
nix run '.#update' -- g:patches
```

### 2. Carve the update into the fork merge

Split the content out of `@` into a described merge commit. The split keeps both parents on the
described commit and adds a fresh empty `@` on top:

```bash
jj split -m 'chore(flake): update' -- flake.lock devenv.lock .flake.patches/
FORK_UPDATE=$(jj log -r @- --no-graph -T 'change_id.short()')
```

Use `jj split`, not `jj describe`. `jj describe` leaves the content in `@` and keeps `@` a
content merge. `jj split` moves the content into `@-` (the fork merge) and leaves `@` empty on
top of it, with a single parent. Split both lock files together — the fork merge carries the full
`flake.lock` and the full `devenv.lock`.

### 3. Insert the upstream update in one command

Insert the public-only commit between the public tip and the fork merge. Use BOTH insert flags:

```bash
jj new --insert-after upstream-tip --insert-before fork-tip -m 'chore(flake): update (public inputs)'
```

`--insert-after upstream-tip` places the new commit on the public chain. `--insert-before
fork-tip` re-parents the fork merge onto it. You need BOTH: `--insert-after` alone leaves the
new commit as a dangling sibling and does NOT re-parent the fork merge. So no separate rebase
step is needed.

`@` is now the upstream update commit, in place between the public tip and the fork merge.
Populate its `flake.lock` with public inputs. `flake-lock-merge` reads the fork merge's lock as
reference and keeps only the public inputs:

```bash
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- "$FORK_UPDATE"
```

`flake-lock-merge` writes to the working copy, so `@` must be the upstream update when you run
it. It removes the fork-specific inputs. This removal is correct.

`flake-lock-merge` writes `flake.lock` only. It cannot write `devenv.lock`
(see [devenv.lock](#devenvlock)). Strip the fork nodes from `devenv.lock` with `jq`, while `@` is
still the upstream update:

```bash
# strip list = fork-only brew-tap nodes = fork flake.lock taps minus public flake.lock taps
STRIP=$(comm -23 \
  <(jj file show -r "$FORK_UPDATE" flake.lock | jq -r '.nodes|keys[]|select(test("^brew-tap--"))' | sort) \
  <(jj file show -r @               flake.lock | jq -r '.nodes|keys[]|select(test("^brew-tap--"))' | sort) \
  | jq -R . | jq -sc .)
jj file show -r "$FORK_UPDATE" devenv.lock | jq --argjson strip "$STRIP" '
  .nodes |= with_entries(select(.key as $k | ($strip|index($k))|not))
  | .nodes |= map_values(if .inputs then .inputs |= with_entries(select((.value|tostring) as $t|($strip|index($t))|not)) else . end)
' | jq -j '.' > devenv.lock
```

The transform reads the fork merge's `devenv.lock`, drops the fork nodes and their input edges,
and writes the result into `@`. It mirrors what `flake-lock-merge` does to `flake.lock`. Use
`jq -j` for the output — native `devenv.lock` has no trailing newline.

### 4. Park the working copy

`@` is still the described upstream update in the middle of the graph. Move it off. Put a fresh
empty working copy on top of the fork merge (single parent). This gives the user a clean review
point on the full lock:

```bash
jj new fork-tip
```

### 5. Verify the topology

```bash
jj log -r 'ancestors(@, 4)' -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"'
jj log -r 'upstream-tip' --no-graph -T 'change_id.short() ++ "\n"'   # → upstream update
jj log -r 'fork-tip'     --no-graph -T 'change_id.short() ++ "\n"'   # → fork merge
```

Confirm the upstream update holds public-only locks. Both `flake.lock` and `devenv.lock` must
NOT contain the fork-specific brew-tap nodes. Compare each lock's tap set against the fork merge:

```bash
for f in flake.lock devenv.lock; do
  echo -n "$f fork-only nodes still present: "
  comm -12 \
    <(jj file show -r upstream-tip "$f" | jq -r '.nodes|keys[]|select(test("^brew-tap--"))' | sort) \
    <(comm -23 \
        <(jj file show -r fork-tip "$f" | jq -r '.nodes|keys[]|select(test("^brew-tap--"))' | sort) \
        <(jj file show -r upstream-tip flake.lock | jq -r '.nodes|keys[]|select(test("^brew-tap--"))' | sort)) \
  | wc -l   # → 0
done
```

### 6. After `jj sync-remotes`, stack new work

The user tests the builds, then runs `jj sync-remotes` to move the bookmarks and push. After the
push, the fork merge and the upstream update are immutable. To start the next cycle — or to stack
any new work — put a fresh empty `@` on top of both tips:

```bash
jj new fork-tip upstream-tip
```

This is the ONLY place a dual-parent `@` is correct. It restores the update workflow's starting
state (`@` on top of `main` and `upstream`). Before the push, keep the single-parent review `@`
from step 4.

---

## Patch file changes

Patch file changes (`.flake.patches/`) are public. They belong on the upstream update, not in
the fork merge. Step 2 puts them in the fork merge first. After step 3, move them down into the
upstream update:

```bash
jj squash --from "$FORK_UPDATE" --into upstream-tip -- .flake.patches/
```

The most common update touches only the lock files. Then this step does nothing and you skip it.

---

## devenv.lock

`devenv.lock` and `flake.lock` share the same node-graph schema. So the same fork nodes come out
of both. But `flake-lock-merge` cannot produce the public `devenv.lock`:

- `flake-lock-merge` regenerates the lock with `nix flake lock --reference-lock-file <ref>`. That
  Nix command **always writes `./flake.lock`** — the name is fixed by Nix, not by the tool. The
  tool's `--path` flag does not redirect it.
- `nix flake lock` also fails on `devenv.lock`, because the file has a `git+file:.` self-input
  that reads as dirty (`error: Lock file contains unlocked input`).
- The two files use different resolvers: `nix flake lock` writes `flake.lock`; `devenv` writes
  `devenv.lock`. Same schema, different writer.

So `devenv.lock` needs the `jq` transform from [step 3](#3-insert-the-upstream-update-in-one-command).
The transform does what `flake-lock-merge` does to `flake.lock`:

1. Start from the **fresh full** `devenv.lock` on the fork merge.
2. Drop the fork-specific nodes (the private brew-tap nodes that the fork adds).
3. Drop the input edges that point at those nodes (on the `nix-configs` node).
4. Write the result with `jq -j` (no trailing newline) into the upstream update.

The strip list is not hardcoded. It is the set of brew-tap nodes present in the fork `flake.lock`
but absent from the public `flake.lock` — so it tracks whatever `flake-lock-merge` removed.

Verify the result: 0 fork nodes, no dangling input edges.

```bash
jq -r '.nodes as $n | [ .nodes|to_entries[]|.key as $o|(.value.inputs//{})|to_entries[]
  | (.value|if type=="array" then .[0] else . end) as $t|select($n[$t]==null)
  | "DANGLING \($o)->\($t)" ] | if length==0 then "edges OK" else .[] end' devenv.lock
```

---

## Post-update fixes

If a build fails, fix the files in `@` (the empty top). Then place the fix on the correct chain,
so the topology stays correct and `jj sync-remotes` picks the right tips. The placement below is
the fork golden path specialized for this workflow — see
[jujutsu-vcs.fork.md § Golden paths](jujutsu-vcs.fork.md#golden-paths) for the general recipes and
the frozen-vs-mutable rule (`-B fork-tip` needs a mutable fork tip; a frozen tree builds forward).
The method depends on whether the tips are pushed yet. Check first:

```bash
jj log -r 'fork-tip' --no-graph -T 'if(immutable, "PUSHED", "not pushed") ++ "\n"'
```

### Public fix, tips NOT pushed yet

A **public** fix (docs, patch files, any non-sensitive change) goes on the upstream chain,
between the upstream update and the fork merge. Use BOTH insert flags:

```bash
jj split --insert-after upstream-tip --insert-before fork-tip \
  -m 'fix(...): description' -- <public-files>
```

`--insert-after upstream-tip` places the new commit on the public chain. `--insert-before
fork-tip` re-parents the fork merge onto it. You need BOTH: `--insert-after` alone leaves the
new commit as a dangling sibling and does NOT re-parent the fork merge, so `fork-tip` would
still point past it and the fix would miss the fork build. After the split, `@` stays the empty
working copy on top of the fork merge.

This step rewrites the fork merge. That is fine while the fork merge is still **mutable** (not
pushed). Do NOT do this after a push — see the next section.

### Public fix, tips ALREADY pushed

After `jj sync-remotes`, both tips are immutable. **NEVER rewrite a pushed commit.** Do NOT use
`--insert-before fork-tip` (it re-parents the immutable fork merge). Do NOT use
`--ignore-immutable`. Both rewrite published history and force a force-push.

Instead, extend both chains **forward** as fast-forwards, then add a **new merge commit** on top.
The upstream fix becomes a child of the upstream tip. A new fork merge joins the old fork merge
with the fix:

```bash
# @ holds the fix content:
jj describe -m 'fix(...): description'          # @ = the fix
jj rebase -r @ -d upstream-tip                  # fix now extends the upstream chain
FIX=$(jj log -r @ --no-graph -T 'change_id.short()')
# new merge on top: old fork merge + the fix — advances the fork chain forward:
jj new fork-tip "$FIX" -m 'chore(fork): merge <fix> from upstream'
jj new fork-tip                                 # park an empty single-parent @ for review
```

The result:

```
@    (empty)                                          single parent = new fork merge
○    new fork merge — "chore(fork): merge <fix>…"     ◄ fork-tip → main
├─╮
│ ○  fix — "fix(…): description"                       ◄ upstream-tip → upstream
◆ │  old fork merge (pushed, immutable)
├─╮
│ ◆  old upstream update (pushed, immutable)
```

Both old tips stay ancestors of the new tips, so `jj sync-remotes` pushes clean fast-forwards —
no force-push, no rewritten history. Confirm before the user pushes:

```bash
jj log -r 'upstream@<fork-remote>::upstream-tip' --no-graph -T 'change_id.short() ++ "\n"'  # old tip is an ancestor
jj log -r 'main@<fork-remote>::fork-tip'         --no-graph -T 'change_id.short() ++ "\n"'  # old tip is an ancestor
```

### Fork-specific fix

A **fork-specific** fix goes on the fork chain, above or in the fork merge (a plain
`jj split -m '...' -- <files>` on the fork side, no insert flags needed).

If the public commit already exists on the chain, and you edit those same files again in `@`,
fold the new edits into that commit instead of making a new one:

```bash
# @ holds fresh edits to files already committed in <public-commit> (e.g. the docs commit):
jj squash --from @ --into <public-commit> -- <files>
```

`jj squash --from @ --into wwvkwkto -- docs/flake-update.fork.md` moves the working-copy edits
of that file into the existing docs commit `wwvkwkto`, and `@` stays empty. Use this to amend a
past commit on the correct chain without disturbing the two tips. `--from @` is the default, so
`jj squash --into wwvkwkto -- <files>` is equivalent. Note `--into` (`-t`) cannot combine with
`-r`/`--revision`; use `--from`/`--into`.

Do NOT run `jj bookmark set` — `jj sync-remotes` moves the bookmarks after the topology is
correct. See [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for the graph surgery.

---

## Testing

Same as [flake-update.md](flake-update.md#testing), with these fork notes:

- Build the fork (macOS) from the fork merge, on the macOS machine. Darwin `switch` requires
  sudo — hand off to the user.
- Build the personal NixOS machines from the upstream update. Run these on the NixOS hosts, or
  from a NixOS builder with `./nixos-rebuild.sh build remote=<hostname>`. You cannot build a
  NixOS host from the macOS machine.
