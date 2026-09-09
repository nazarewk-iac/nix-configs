---
name: flake-update-fork
description: Flake update with fork merge — fetch and reconcile, split the update onto fork/upstream sides, run flake-lock-merge, strip devenv.lock, prove completion, let jj sync-remotes place bookmarks. Use when updating flake inputs in a repo with both a public and a private fork remote.
type: Skill
timestamp: 2026-09-09T18:00:00+02:00
---

Full reference (stable URLs — a consumer repo has no `docs/` directory):

- [flake-update.fork.md](https://github.com/nazarewk-iac/nix-configs/blob/main/docs/flake-update.fork.md)
- [jujutsu-vcs.fork.md](https://github.com/nazarewk-iac/nix-configs/blob/main/docs/jujutsu-vcs.fork.md)
  — `jj fork-help` prints the same topology locally.

Base workflow: see the `flake-update` skill. This skill **overrides every step** of it.

## Two rules that override everything

1. **NEVER run `jj bookmark set`** for `main` or `upstream`. `jj sync-remotes` moves both from the
   topology (`upstream-tip` → `upstream`, `fork-tip` → `main`). You build the topology only. The
   user runs `jj sync-remotes` and pushes.
2. **`@` is a plain empty change with one parent.** It holds no content and never sits in the
   middle of the graph. `nix run '.#update'` leaves the locks in a merge `@` transiently. Carve
   them into a described commit at once, and keep `@` empty above it.

## Step 0 — fetch, then reconcile

Never skip this. `nix run '.#update'` never fetches, and every later placement reads a
remote-tracking ref. A stale ref puts a commit on the wrong chain.

```bash
jj git fetch --all-remotes
jj log -r 'upstream-incoming'   # must print nothing
jj log -r 'fork-incoming'       # must print nothing
```

| Both empty | Action |
|---|---|
| yes | go on to step 1 |
| `upstream-incoming` has commits | rebase the local upstream chain onto the new public tip |
| `fork-incoming` has commits | rebase the fork chain onto the new fork tip |
| both have commits | rebase the upstream chain first, then the fork chain |

A rebase is needed in this one case only. Do not rebase for any other reason.

## Step 1 — name the start state

```bash
jj log -r '@' --no-graph -T 'if(empty,"empty","content") ++ " " ++ parents.len() ++ "\n"'
jj log -r 'to-rebase'                        # not empty → route or publish the stack first
jj log -r 'fork-leaked & ::upstream-safe'    # not empty → reorder first
```

| Start state | May start an update |
|---|---|
| `empty 2` — empty `@` above a mutable tree merge | yes |
| `empty 1` — empty `@` above a frozen (pushed) merge | yes; step 3b manufactures a new merge |
| `content …` — `@` holds work | no; carve or park the work first |
| unrouted stack in `to-rebase` | no; route each commit to its chain first |
| a public commit above a fork-only commit (`fork-leaked`) | no; reorder first |

Reorder a public commit down onto the upstream chain:

```bash
jj rebase -r <safe-commit> -A upstream-tip -B tree-merge
```

## Step 2 — update

```bash
nix run '.#update'
devenv update      # devenv.lock has a separate resolver — BOTH are required
```

A patch failed? Find the cause first — see the `flake-patches` skill. Never default to deletion.

## Step 3 — carve the full locks onto the fork side

```bash
jj split -m 'chore(flake): update' -- flake.lock devenv.lock .flake.patches/
FORK_UPDATE=$(jj log -r @- --no-graph -T 'change_id.short()')
```

Use `jj split`, not `jj describe`. `describe` keeps the content in `@` and leaves `@` a content
merge. `split` moves the content into `@-` and keeps `@` empty.

### Step 3b — the insert needs a mutable tree merge

```bash
jj log -r 'tree-merge & mutable()' --no-graph -T '"exists\n"'
jj new --no-edit -B @ -m 'chore(upstream): merge'   # ONLY when the line above prints nothing
```

## Step 4 — insert the public-only update

BOTH flags, one command. `--insert-after` adds the commit; `--insert-before` re-parents the merge.

```bash
jj new --insert-after upstream-tip --insert-before tree-merge -m 'chore(flake): update (public inputs)'
```

> **`-B tree-merge`, never `-B fork-tip`.** `fork-tip` equals the tree merge only when no fork-only
> commit sits above it. When one does, `fork-tip` is that leaf, and `-B fork-tip` gives the leaf a
> second parent — it turns an ordinary fork commit into a merge and leaves the tree merge
> untouched. `-B tree-merge` is correct in both shapes.

> **`upstream-tip` can resolve below the merge.** The `fork` alias ends in `::`, so it tags every
> descendant of the fork bookmark — the tree merge included. `upstream-chain` therefore never holds
> a commit above the merge. Read `upstream-tip` as "the top of the public chain **below** the
> merge". That is exactly what the insert needs.

## Step 5 — write the public-only locks

```bash
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- "$FORK_UPDATE"   # flake.lock only
```

`flake-lock-merge` writes `flake.lock` only. It calls `nix flake lock --reference-lock-file`, which
always writes `./flake.lock`, and that command fails on `devenv.lock`'s `git+file:.` self-input.
Strip `devenv.lock` with `jq`:

```bash
STRIP=$(comm -23 \
  <(jj file show -r "$FORK_UPDATE" flake.lock | jq -r '.nodes[.root].inputs|keys[]' | sort) \
  <(jj file show -r @               flake.lock | jq -r '.nodes[.root].inputs|keys[]' | sort) \
  | jq -R . | jq -sc .)
test "$STRIP" != '[]' || { echo 'FAIL: empty strip list — did flake-lock-merge run?'; exit 1; }
jj file show -r "$FORK_UPDATE" devenv.lock > /tmp/fork.devenv.lock
jq --argjson strip "$STRIP" '
  .nodes |= with_entries(select(.key as $k | ($strip|index($k))|not))
  | .nodes |= map_values(if .inputs then .inputs |= with_entries(select((.value|tostring) as $t|($strip|index($t))|not)) else . end)
' /tmp/fork.devenv.lock | jq -j '.' > /tmp/public.devenv.lock
mv /tmp/public.devenv.lock devenv.lock
```

> **Never redirect into the file a `jj` read is reading.** `jj file show -r @ devenv.lock >
> devenv.lock` truncates the file before the read starts. `jj file show` then snapshots the empty
> file into `@`, and jj rebases that empty file into every descendant. Recover with `jj op restore
> <op-before-the-snapshot>`. Always read into a temporary file, then `mv`.

Compare the **root node's inputs**, not a name prefix. A prefix filter misses any fork input whose
name does not carry the prefix. Assert the result:

```bash
jq -e '.nodes|to_entries|map(select(.value.inputs == null))|length == 0' devenv.lock   # no "inputs": null
jq -e --argjson s "$STRIP" '[.nodes[]|.inputs//{}|to_entries[].value|tostring] as $r
  | ($s - ($s - $r))|length == 0' devenv.lock                                          # no dangling edge
jq -e '.nodes[.root].inputs|length > 0' devenv.lock                                    # root still wired
```

A node with no inputs must **omit** the key. `resolve-lock.nix` reads `node.inputs or { }`, and the
`or` operator answers a missing attribute only — never `null`. Assertion 2 cannot catch a stripped
sub-node that nothing references, so keep the root-input derivation above.

`jq -j` writes no trailing newline, which matches a native `devenv.lock`.

## Step 6 — move the patch files down

```bash
jj squash --from "$FORK_UPDATE" --into upstream-tip -- .flake.patches/
```

Skip this when the update touched the lock files only.

## Step 7 — park an empty working copy

```bash
jj new fork-tip
```

One parent, no content. It reaches the upstream update through the merge.

## Step 8 — prove the run is complete, then hand off

```bash
bash hack/flake-update-complete.sh
```

The check is mandatory. An incomplete run looks finished, because the two tips already differ even
when the public chain holds no update at all.

Then run the build gates, fetch once more, and hand off. **Never run `jj bookmark set` and never
run `jj sync-remotes`** — the user does both, and the user pushes.

Resulting shape (`@` has one parent; the merge sits directly on the upstream update):

```
@                       empty working copy, one parent
○   tree merge          "chore(flake): update"                  full locks    ◄ fork-tip → main
├─╮
│ ○ upstream update     "chore(flake): update (public inputs)"  public locks  ◄ upstream-tip → upstream
◆ │ main@<fork-remote>
├─╮
│ ◆ upstream@<fork-remote>
```

## Step 9 — after the user syncs

Both tips are then immutable, so stack new work over both:

```bash
jj new fork-tip upstream-tip
```

That is the only correct dual-parent `@`.

## Post-update fixes

**Choose the chain by content, not by the host that found the failure.** A generic fix found on a
fork host is public. Test it:

```bash
jj fork-audit -q --color=never '@'    # read the OUTPUT, not the exit code
```

Then check whether the tips are pushed:

```bash
jj log -r 'fork-tip' --no-graph -T 'if(immutable, "PUSHED", "not pushed") ++ "\n"'
```

### Case A — tips NOT pushed yet (mutable)

```bash
jj split --insert-after upstream-tip --insert-before tree-merge -m 'fix(...): description' -- <files>
# amend an EXISTING public commit instead:
jj squash --from @ --into <public-commit> -- <files>
```

### Case B — tips ALREADY pushed (immutable)

Never rewrite a pushed commit. Do not use `--insert-before` on a pushed merge and do not use
`--ignore-immutable`. Extend both chains forward, then add a NEW merge on top:

```bash
jj describe -m 'fix(...): description'          # @ = the fix
jj rebase -r @ -d upstream-tip                  # the fix extends the upstream chain
FIX=$(jj log -r @ --no-graph -T 'change_id.short()')
jj new fork-tip "$FIX" -m 'chore(fork): merge <fix> from upstream'
jj new fork-tip                                 # park an empty one-parent @
```

Both old tips stay ancestors of the new tips, so both pushes are fast-forwards. Confirm:

```bash
jj log -r 'upstream@<fork-remote>::upstream-tip' --no-graph -T 'change_id.short() ++ "\n"'
jj log -r 'main@<fork-remote>::fork-tip'         --no-graph -T 'change_id.short() ++ "\n"'
```

## Agent notes

- **Fetch first, and fetch again before the hand-off.** The only built-in fetch runs inside
  `sync-upstream`, at push time — too late to change a placement.
- **`jj fork-audit` with no revset scans both chains, so it normally exits 1 in a fork repo.** Exit
  1 is its normal state. Pass an explicit revset and read the output. The pattern list also does
  not match lock content: a commit that changed 4 fork-only lock nodes exited 0.
- `upstream@<fork-remote>` is the stable anchor — never use bare `upstream` in a revset.
- Pass `-m 'msg'` and `-- <files>` to `jj split`/`jj describe`/`jj squash`. They open an editor by
  default. `jj new` and `jj rebase` need no editor.
- The two pushes are not atomic, and `sync-remotes` publishes the **public** chain first. Finish
  every check before the hand-off; the public push is not reversible.
- Build the fork host from the tree merge, on that host. Build a NixOS host from the upstream
  update, on a NixOS host. You cannot build a NixOS host from macOS.
- Never run `switch` — hand off to the user (it needs sudo).
