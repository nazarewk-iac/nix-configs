---
type: Playbook
description: Extends the flake update workflow for repos maintaining a private fork remote — fetch, reconcile, start state, placement, strip, and the completion check.
timestamp: 2026-09-09T18:00:00+02:00
---

# Flake Update — Fork Workflow

> **Agent note:** The agent rule `.agents/rules/flake-update.fork.md` is installed as
> `.claude/rules/flake-update.fork.md` by the `kdn.jj.fork` slot
> (`modules/slots/jj/fork/default.nix`). This file is the full doc that rule points to. See also
> [flake-update.md](flake-update.md) for the base workflow and
> [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for fork-specific jj patterns.
>
> In non-interactive contexts: `jj split`/`jj describe` are safe with `-m` and `-- <files>`.
> `jj new` and `jj rebase` are non-interactive. `upstream@<fork-remote>` is the stable anchor —
> never use bare `upstream` in revsets.

Extends [flake-update.md](flake-update.md) for repos that maintain a private fork remote
alongside the public remote. See [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for the
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

2. **`@` is a plain empty change on top of the fork chain.** `@` has a single parent. `@` never
   holds content and never sits in the middle of the graph. When `nix run '.#update'` writes
   `flake.lock` into `@`, that state is transient; step 3 carves the content into a described
   commit and leaves `@` empty on top of it. Content in `@`, or `@` described in the middle of
   the graph, is a mistake — fix it at once.

   **One exception, after `jj sync-remotes`.** Once you push, the fork merge and the upstream
   update become immutable. To stack new work you then run `jj new fork-tip upstream-tip`, so `@`
   gets both tips as parents. This dual-parent `@` restores the update workflow's starting state
   (`@` on top of `main` and `upstream`) for the next cycle. This is the ONLY place a dual-parent
   `@` is correct. See [step 9](#9-after-jj-sync-remotes-stack-new-work).

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
│ ◆  upstream@<fork-remote>                            public parent
```

- **upstream update**: public inputs only, in both `flake.lock` and `devenv.lock` (patch file
  changes go here too). Its parent is the public tip.
- **fork merge**: `flake.lock` and `devenv.lock` with all inputs (public + fork-specific). Its
  two parents are the **upstream update** and the fork `main`. So the fork merge sits directly on
  top of the upstream update — that link is the point of the shape.
- **`@`**: a plain empty working copy with a single parent. There is no `@` → upstream edge. `@`
  reaches the upstream update through the fork merge.

The fork merge carries the full locks, so the fork build uses them. The upstream update carries
the public-only locks, so the public hosts build from them in parallel.

Both lock files get the same split. `flake.lock` and `devenv.lock` share the same node schema,
so the fork-specific inputs come out of both the same way. See [devenv.lock](#devenvlock) for the
tool difference.

---

## Quick summary

```bash
# STEP 0 — fetch first. Every placement command reads a remote-tracking ref.
jj git fetch --all-remotes
jj log -r 'upstream-incoming'          # must be empty before you go on
jj log -r 'fork-incoming'              # must be empty before you go on
jj log -r 'merge-frozen'               # empty → the tree merge is mutable

# STEP 1 — name the start state. Only (i) and (v) may start an update.
jj log -r '@' --no-graph -T 'if(empty,"empty","content") ++ " " ++ parents.len() ++ "\n"'
jj log -r 'to-rebase' --no-graph -T 'change_id.short() ++ "\n"'
jj log -r 'fork-leaked & ::upstream-safe' --no-graph -T 'change_id.short() ++ "\n"'

# STEP 2 — run the update
nix run '.#update'
devenv update                       # updates devenv.lock (separate engine from flake.lock)
# patch failed? see docs/flake-patches.md

# STEP 3 — carve the full locks into a fork-side commit; @ becomes empty on top:
jj split -m 'chore(flake): update' -- flake.lock devenv.lock .flake.patches/
FORK_UPDATE=$(jj log -r @- --no-graph -T 'change_id.short()')

# STEP 3b — a mutable merge must exist before the insert:
jj log -r 'tree-merge & mutable()' --no-graph -T '"exists\n"'
jj new --no-edit -B @ -m 'chore(upstream): merge'     # ONLY when the line above prints nothing

# STEP 4 — insert the public-inputs commit after the public tip and before the merge:
jj new --insert-after upstream-tip --insert-before tree-merge -m 'chore(flake): update (public inputs)'
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- "$FORK_UPDATE"   # flake.lock only

# STEP 5 — strip the fork nodes from devenv.lock. Never redirect into the file you read.
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

# STEP 6 — move the patch files down onto the public side (a lock-only update skips this):
jj squash --from "$FORK_UPDATE" --into upstream-tip -- .flake.patches/

# STEP 7 — park a fresh empty working copy on top of the fork chain (single parent):
jj new fork-tip

# STEP 8 — check, build, fetch again, hand off. NEVER run `jj bookmark set`.
bash hack/flake-update-complete.sh
```

---

## Step-by-step

### 0. Fetch, then reconcile

**Run this first, every time.** Every placement decision in this procedure reads a
remote-tracking ref. A stale ref sends the public-inputs commit to the wrong parent, and the
late fetch inside `sync-upstream` then rejects the push.

`nix run '.#update'` cannot fetch for you. `flake-update.sh` runs `nix flake update` and the
patch updater only. The single fetch in the whole system sits inside the `sync-upstream` alias,
and that alias runs at **push** time — far too late to change a placement.

```bash
jj git fetch --all-remotes
jj log -r 'upstream-incoming' -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"'
jj log -r 'fork-incoming'     -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"'
jj log -r 'merge-frozen'      # empty → the tree merge is mutable
```

Then apply this table. Do not go on while either incoming set holds a commit.

| Outcome | Detection | Action |
|---|---|---|
| nothing moved | both incoming sets are empty | go on to step 1. **No rebase.** |
| the public tip moved | `upstream-incoming` is not empty | integrate the public tip **before** the update, so the new locks resolve against the new public base. Mutable tree merge: `jj rebase -s 'roots(upstream-local)' -d 'upstream-incoming-tip'`. Frozen tree merge: `jj new fork-tip upstream-incoming-tip -m 'chore(upstream): merge'`, then `jj new`. |
| the fork tip moved | `fork-incoming` is not empty | the fetched fork commits are immutable, because `trunk()` is `main@<fork-remote>`. Build forward: `jj new fork-tip fork-incoming-tip -m 'chore(fork): merge fork main'`, then `jj new`. |
| both moved | both sets are not empty | do the public integration first, then the fork merge forward. Re-read `merge-frozen` and `fork-leaked` after each step. |

**A rebase is genuinely required in one case only:** the public tip moved **and** the tree merge
is still mutable. That is a real topology fix, which `.agents/rules/jujutsu-vcs.md` permits.
Every other outcome builds forward with `jj new` and needs no rebase.

**Which aliases a fetch can change.** A fetch that advances `main@<fork-remote>` moves `trunk()`,
so commits that were mutable turn immutable. A placement command that needs a mutable merge can
stop working between two steps of the same procedure. These aliases change value after a fetch:
`trunk()`, `immutable()`/`mutable()`, `fork`, `upstream-chain`/`fork-chain`,
`upstream-tip`/`fork-tip`, `pushed*`, `merge-frozen`, `upstream-incoming*`, `fork-incoming*`,
`upstream-local`. These do not: `tree-merge`, `to-rebase`, `fork-direct`, `upstream-safe`,
`fork-leaked`. So `upstream-safe` and `fork-leaked` are safe to read at any time; every topology
alias is not.

**Fetch when you own the working copy.** jj snapshots the working copy before it runs a command
that reads `@`, so uncommitted content is safe — it becomes part of `@`. But that snapshot
**writes** the repo. When another agent writes files in the same working copy at the same time,
the snapshot races it, and this repo has already recorded file truncation from such a race. Do
not fetch in parallel with another writer.

### 1. Name the start state, and fix it first

The rest of this procedure assumes a specific start state. **That state is not the usual one.**
`jj sync-remotes` leaves `@` empty with two parents, but the resting shape documented in
[jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) is a single-parent empty `@` on the fork chain. The
dual-parent start state therefore exists only in the minutes right after a publish.

Run all three detection commands:

```bash
jj log -r '@' --no-graph -T 'if(empty,"empty","content") ++ " " ++ parents.len() ++ "\n"'
jj log -r 'to-rebase' --no-graph -T 'change_id.short() ++ "\n"'
jj log -r 'fork-leaked & ::upstream-safe' --no-graph -T 'change_id.short() ++ "\n"'
```

| # | Start state | Detection | First step |
|---|---|---|---|
| i | `@` empty, two parents, right after `jj sync-remotes` | prints `empty 2`; `to-rebase` is empty | fetch, reconcile, then run the update. This is the documented path. |
| ii | `@` empty on a linear stack of local commits | prints `empty 1`; `to-rebase` is not empty; `tree-merge & merges() & mutable()` is empty | **work first:** route or publish the stack, so the two-chain shape exists. Then update. |
| iii | `@` holds content | prints `content …` | **work first:** route the content out of `@` with golden path 4 in [test_placement.md](../checks/jj-experiments/test_placement.md). Leave `@` empty. Never mix that content with the update. |
| iv | local commits mix `upstream-safe` and fork-only, safe above fork-only | `fork-leaked & ::upstream-safe` is not empty | **work first:** reorder, see below. Then update. |
| v | `@` empty, one parent, `to-rebase` empty, the tree merge is frozen | prints `empty 1`; `to-rebase` empty; `merge-frozen` not empty | fetch, reconcile, then update. Step 3b must manufacture a mutable merge. |

**States (ii), (iii) and (iv) need work before the update starts.** Only (i) and (v) may start
one.

#### Case (iv), the hard one

An `upstream-safe` commit that sits **above** a fork-only commit can never reach the public
remote, because its ancestry holds the fork-only commit. The topology alias makes this worse: the
`fork` alias tags every descendant of the fork bookmark, so `upstream-tip` never selects a commit
above the tree merge and `sync-upstream` never offers it. Those commits are content-clean and
still invisible. They stay on the fork chain for ever until somebody reorders them.

**Reorder before the update, not after.** Three reasons: the placement step reads `upstream-tip`
and `fork-tip`, and both answer wrongly while the stack is linear; the update commit must be the
newest fork-side commit, so a later reorder has to rewrite it while it holds the mixed locks; and
a reorder before the update touches only mutable, unpublished commits.

```bash
# @ must be empty — route any content out first.

# 1. manufacture a mutable merge above the stack, when none exists:
jj log -r 'tree-merge & mutable()' --no-graph -T '"exists\n"'
jj new --no-edit -B @ -m 'chore(upstream): merge'      # only when the line above prints nothing

# 2. move each upstream-safe commit onto the public chain, OLDEST FIRST:
jj rebase -r <safe-commit> -A upstream-tip -B tree-merge
#    re-read upstream-tip and tree-merge after every move — both can change

# 3. verify:
jj log -r 'to-rebase'         # only the fork-only commits stay above the merge
jj log -r 'fork-leaked'       # only intended fork leaves
jj fork-audit -q --color=never 'upstream-safe'
```

Step 2 repeated over several commits is **unverified** — no case in
`checks/jj-experiments/` covers it. Move one commit, verify, then move the next.

An operator who does not want a rebase has one alternative: publish the stack to the private
remote only, and defer the public contribution. That leaves the public work unpublished, so it is
a worse outcome.

### 2. Run the update

```bash
nix run '.#update'
devenv update
```

`nix run '.#update'` updates all flake inputs and applies patches. `devenv update` updates
`devenv.lock`, which has a separate resolver (see [devenv.lock](#devenvlock)). **Both commands are
required.** A run that skips `devenv update` leaves `devenv.lock` stale, and no later step catches
it.

A patch failure has its own decision procedure — see [flake-patches.md](flake-patches.md) and the
`flake-patches` skill. Do not guess a branch: the correct action depends on why the patch failed.

### 3. Carve the update into the fork merge

Split the content out of `@` into a described commit. The split adds a fresh empty `@` on top:

```bash
jj split -m 'chore(flake): update' -- flake.lock devenv.lock .flake.patches/
FORK_UPDATE=$(jj log -r @- --no-graph -T 'change_id.short()')
```

Use `jj split`, not `jj describe`. `jj describe` leaves the content in `@`. `jj split` moves the
content into `@-` and leaves `@` empty on top of it, with a single parent. Split both lock files
together — the fork-side commit carries the full `flake.lock` and the full `devenv.lock`.

### 3b. Make sure a mutable merge exists

**This is a precondition, not an optional check.** Step 4 re-parents the tree merge onto the new
commit, so the tree merge must be **mutable**. On a frozen tree the command would try to rewrite
an immutable commit and fail.

```bash
jj log -r 'tree-merge & mutable()' --no-graph -T '"exists\n"'
jj new --no-edit -B @ -m 'chore(upstream): merge'     # ONLY when the line above prints nothing
```

From state (i) the split in step 3 already left a mutable merge, so this step does nothing. From
state (v) it manufactures one above the frozen merge, and the frozen merge is untouched. This is
the proven step — golden path 1 in
[test_placement.md](../checks/jj-experiments/test_placement.md).

### 4. Insert the public-inputs commit

Insert the public-only commit between the public tip and the tree merge. Use BOTH insert flags:

```bash
jj new --insert-after upstream-tip --insert-before tree-merge -m 'chore(flake): update (public inputs)'
```

`--insert-after upstream-tip` places the new commit on the public chain. `--insert-before
tree-merge` re-parents the merge onto it, so the whole fork chain above the merge inherits it.
You need BOTH: `--insert-after` alone leaves the new commit as a dangling sibling and does NOT
re-parent the merge, so the fork build would never see the public commit.

> **Use `-B tree-merge`, not `-B fork-tip`, whenever a fork leaf sits above the merge.**
> The golden path in [test_placement.md](../checks/jj-experiments/test_placement.md) writes
> `-B fork-tip` because in its base graph the merge **is** the fork tip. When a fork-only leaf
> commit sits above the merge, `fork-tip` is that leaf, and `-B fork-tip` gives the leaf a second
> parent — it turns an ordinary fork commit into a merge and leaves the tree merge untouched.
> `-B tree-merge` is correct in both shapes, because the tree merge is the join point by
> definition.

> **Why `upstream-tip` can resolve *below* the tree merge.**
> `modules/slots/jj/fork/default.nix` defines the third term of the `fork` alias as
> `((remote_bookmarks(remote=<fork-remote>) ~ upstream@<fork-remote>)::)`. The `::` suffix tags
> **every descendant** of the fork bookmark. So `upstream-chain`, which is
> `~description("") & ~fork`, can never hold a commit above the tree merge — whatever that commit
> contains. On any graph that already carries local work, `upstream-tip` therefore points below
> the merge. That is not a bug in the alias; it is why step 1 rejects start states (ii) and (iv).
> `upstream-safe` does **not** have this property: it is `to-rebase & ~fork-direct`, and
> `fork-direct` tests **content**, not topology.

Now populate the new commit's `flake.lock` with the public inputs. `flake-lock-merge` reads the
fork-side lock as reference and keeps only the public inputs:

```bash
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- "$FORK_UPDATE"
```

`flake-lock-merge` writes to the working copy, so `@` must be the public-inputs commit when you
run it. It removes the fork-specific inputs. That removal is correct. The pinned-rev form avoids
a rebuild of the tool against the new inputs; the plain `nix run '.#flake-lock-merge'` form is
also correct.

### 5. Strip the fork nodes from `devenv.lock`

`flake-lock-merge` writes `flake.lock` only. It cannot write `devenv.lock`
(see [devenv.lock](#devenvlock)). Strip the fork nodes with `jq`, while `@` is still the
public-inputs commit.

> ⚠️ **Never redirect into the file the same pipeline reads through `jj`.** The shell opens the
> redirect **before** it starts the pipeline, so the file is already 0 bytes when `jj file show`
> runs. `jj file show` then snapshots the working copy, and the empty file becomes the content of
> `@`. Because the fork-side commit is a **descendant** of `@`, jj rebases the empty file into it,
> and the read returns nothing. One measured run wiped `devenv.lock` in `@` and in every
> descendant; `jj op restore <op-before-the-snapshot>` recovered it. Write to a temporary file,
> then `mv` it into place. The general rule is in [jujutsu-vcs.md](jujutsu-vcs.md).

```bash
# The strip list is the root-input difference. NO name prefix filter — a fork-only input with
# any other name must not slip through (O9).
STRIP=$(comm -23 \
  <(jj file show -r "$FORK_UPDATE" flake.lock | jq -r '.nodes[.root].inputs|keys[]' | sort) \
  <(jj file show -r @               flake.lock | jq -r '.nodes[.root].inputs|keys[]' | sort) \
  | jq -R . | jq -sc .)

# An empty list makes the transform a no-op and every fork node stays in the public lock (O10).
test "$STRIP" != '[]' || { echo 'FAIL: empty strip list — did flake-lock-merge run?'; exit 1; }

jj file show -r "$FORK_UPDATE" devenv.lock > /tmp/fork.devenv.lock
jq --argjson strip "$STRIP" '
  .nodes |= with_entries(select(.key as $k | ($strip|index($k))|not))
  | .nodes |= map_values(if .inputs then .inputs |= with_entries(select((.value|tostring) as $t|($strip|index($t))|not)) else . end)
' /tmp/fork.devenv.lock | jq -j '.' > /tmp/public.devenv.lock
mv /tmp/public.devenv.lock devenv.lock
rm -f /tmp/fork.devenv.lock /tmp/public.devenv.lock
```

The transform reads the fork-side `devenv.lock`, drops the fork nodes and their input edges, and
writes the result into `@`. It mirrors what `flake-lock-merge` does to `flake.lock`. Use `jq -j`
for the output — a native `devenv.lock` has no trailing newline.

**Use this transform as written. A hand-written substitute is not permitted.** One hand-written
variant wrote `"inputs": null` on 49 nodes that hold no inputs, and both locks carried the fault
to the push. `devenv build shell` then failed with `error: expected a set but found null`, because
`resolve-lock.nix` reads `node.inputs or { }` and the `or` operator answers a **missing**
attribute only — it does not answer `null`. A node with no inputs must **omit** the key.
`flake.lock` never writes `"inputs": null`. The transform above is null-safe: its
`if .inputs then … else . end` guard is what keeps it so.

#### Assert the structure after the strip

Run these three assertions on **both** lock files. No earlier step catches a malformed lock.

```bash
for f in flake.lock devenv.lock; do
  # 1. no node holds "inputs": null
  n=$(jq -r '[.nodes|to_entries[]|select(.value.inputs==null and (.value|has("inputs")))]|length' "$f")
  test "$n" = 0 || echo "FAIL: $f has $n node(s) with \"inputs\": null"

  # 2. every string input value names a node that exists (referential integrity).
  #    Check the STRING form only. An array value such as ["nixpkgs-lib"] is a follows path from
  #    the ROOT node, not a node key, so a check that reads .[0] as a key reports a false
  #    dangling edge on every follows (measured: 3 false positives on this repo's flake.lock).
  #    hack/flake-update-complete.sh resolves the array form properly.
  d=$(jq -r '.nodes as $n | [ .nodes|to_entries[]|.key as $o | (.value.inputs//{})|to_entries[]
    | .value | select(type=="string") | select($n[.]==null) ] | length' "$f")
  test "$d" = 0 || echo "FAIL: $f has $d dangling input edge(s)"
done

# 3. the public node count equals the fork node count minus the strip-list length
for f in flake.lock devenv.lock; do
  fork=$(jj file show -r "$FORK_UPDATE" "$f" | jq '.nodes|length')
  pub=$(jq '.nodes|length' "$f")
  want=$(( fork - $(echo "$STRIP" | jq 'length') ))
  test "$pub" = "$want" || echo "FAIL: $f node count $pub, expected $want"
done
```

Assertion 3 holds because the transform deletes only the nodes named in `$STRIP`; it does not
delete transitively. **Known limit:** a stripped root input that carried its own sub-nodes leaves
those sub-nodes present but unreachable. Assertion 2 does not catch that, because an unreachable
node has no dangling edge. The completion check in
[`hack/flake-update-complete.sh`](../hack/flake-update-complete.sh) adds a reachability
assertion for it.

### 6. Move the patch files down

Patch file changes (`.flake.patches/`) are public. They belong on the public-inputs commit, not on
the fork side. Step 3 puts them on the fork side first. Move them down now:

```bash
jj squash --from "$FORK_UPDATE" --into upstream-tip -- .flake.patches/
```

**A lock-only update skips this step.** Check first — `jj diff -r "$FORK_UPDATE" --name-only` tells
you whether the update touched `.flake.patches/` at all.

### 7. Park the working copy

`@` is still the described public-inputs commit in the middle of the graph. Move it off. Put a
fresh empty working copy on top of the fork chain (single parent). This gives the user a clean
review point on the full lock:

```bash
jj new fork-tip
```

### 8. Check, build, fetch again, hand off

#### 8a. The completion check

**An incomplete run looks finished.** Printing three revset values and asking the operator to
"confirm" asserts nothing. Run the script instead — every line must PASS and it must exit 0:

```bash
bash hack/flake-update-complete.sh
```

It asserts the topology, that the public commit really changed **both** locks, that no fork-only
lock node reached the public commit, that neither lock holds a structural fault, and that `@` is
empty with one parent. Two of its assertions matter more than the rest:

- "two tips exist and differ" is worthless on its own — the two tips already differ when the
  public chain holds no update at all.
- the fork-only-node check must run **after** the differs-from-remote check. With no public
  commit it counts 0 fork nodes and passes for the wrong reason.

#### 8b. The content audit

```bash
jj fork-audit -q --color=never 'upstream-tip'
```

Always pass `-q`, so the tool prints no pattern. `jj fork-audit` greps file **content** at a
revision, which the name-only push hook cannot do.

> **This audit is a second net, not the gate.** Measured: the pattern list does not match lock
> content. `jj fork-audit` reported "no fork-sensitive content found" and exited **0** on a commit
> that changed 4 fork-only lock nodes. The gate for lock content is the **structural** check in
> 8a, which needs no pattern list at all.
>
> `jj fork-audit` with no revset argument scans every mutable, described, non-empty commit on
> **both** chains. In a repo that carries fork commits it therefore exits 1 as its normal state.
> Read the per-commit output, or pass an explicit revset as above — do not read the bare exit
> code as a verdict.

#### 8c. Build both chains

Build the devenv shell on each chain. **Nothing else in this procedure builds it**, so a broken
`devenv.lock` otherwise reaches the push — that is exactly how the `"inputs": null` fault
survived every check and appeared only when the operator entered the shell.

```bash
jj new upstream-tip && devenv build shell     # must exit 0
jj new fork-tip     && devenv build shell     # must exit 0
```

#### 8d. Evaluate every host, on both chains

An input bump can break one platform only. Evaluation costs no build and catches the whole class:

```bash
# for every nixos host:
nix eval --raw '.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath'
# for every darwin host:
nix eval --raw '.#darwinConfigurations.<host>.config.system.build.toplevel.drvPath'
```

Run it on both chains. This gate is not optional: one measured update bumped an input that broke
**every** darwin host, and the operator found it only after the graph was already split and
parked. Evaluation is cheap; a re-split is not.

#### 8e. The build gates, and their order

| Build | Chain | Gates |
|---|---|---|
| `./nixos-rebuild.sh build remote=<hostname>` | `upstream-tip` | the **public** push |
| `nix run '.#darwin-rebuild' -- build` | `fork-tip` | the **private** push |

A NixOS host cannot be built from macOS, and a Darwin host must be built on a Darwin machine or
through `remote=`. `switch` needs sudo — hand it to the user.

#### 8f. Fetch again, then hand off

The build phase can run for hours. A second fetch costs seconds and turns a push rejection into a
cheap reconcile:

```bash
jj git fetch --all-remotes
jj log -r 'upstream-incoming'   # must stay empty
jj log -r 'fork-incoming'       # must stay empty
```

Then hand off. The user runs `jj sync-remotes`.

> ⚠️ **The two pushes are not atomic, and the public one runs first.** `jj sync-remotes` runs
> `jj sync-upstream` before it touches the fork, so the public chain is published before the
> operator is even asked about the fork push. A cancelled fork push leaves the public side
> published, and the public push uses raw git, so it leaves no jj operation and `jj op undo`
> cannot reach it. Run the completion check and both builds **before** the hand-off, not after.

### 9. After `jj sync-remotes`, stack new work

After the push, the fork merge and the public commit are immutable. To start the next cycle — or
to stack any new work — put a fresh empty `@` on top of both tips:

```bash
jj new fork-tip upstream-tip
```

This is the ONLY place a dual-parent `@` is correct. It restores the update workflow's starting
state (start state (i)). Before the push, keep the single-parent review `@` from step 7.

---

## devenv.lock

`devenv.lock` and `flake.lock` share the same node-graph schema. So the same fork nodes come out
of both. But `flake-lock-merge` cannot produce the public `devenv.lock`:

- `flake-lock-merge` regenerates the lock with `nix flake lock --reference-lock-file <ref>`. That
  Nix command **always writes `./flake.lock`** — the name is fixed by Nix, not by the tool. The
  tool's `--path` flag picks the path to **read** in the jj tree; it does not redirect the output.
- `nix flake lock` also fails on `devenv.lock`, because the file has a `git+file:.` self-input
  that reads as unlocked (`error: Lock file contains unlocked input`).
- The two files use different resolvers: `nix flake lock` writes `flake.lock`; `devenv` writes
  `devenv.lock`. Same schema, different writer.

### The `nix-configs` node has no rev, and that is correct

Do not treat this as an unfinished update. In `devenv.lock`, exactly one node — `nix-configs`, the
self-input declared in `devenv.yaml` as `url: git+file:.` — holds no `rev`, no `narHash` and no
`lastModified`:

```json
{"type": "git", "url": "file:."}
```

Nix strips every volatile attribute from the `locked` node of a **local** input, and a git input
counts as local when its url scheme is `file` (`src/libflake/lockfile.cc`, `src/libfetchers/git.cc`).
The comment there reads "Strip volatile attributes from local inputs to avoid lock file churn. Local
inputs are always fetched fresh". devenv depends on that: a local input must stay a live tree, so the
eval cache tracks edits to the repo. devenv ships the same shape for its own self-input.

**No command, flag or url form can pin it**, because the strip sits in the serializer downstream of
all of them. So `nix run '.#update'` plus `devenv update` leave this node correct, and the procedure
needs no extra step. The same local-input exemption is why the parser accepts the node, and why the
`nix flake lock` failure above is specific to that command rather than a sign of a bad lock.

So `devenv.lock` needs the `jq` transform from [step 5](#5-strip-the-fork-nodes-from-devenvlock).
The transform does what `flake-lock-merge` does to `flake.lock`:

1. Start from the **fresh full** `devenv.lock` on the fork-side commit.
2. Drop the fork-specific root-input nodes.
3. Drop the input edges that point at those nodes.
4. Write the result with `jq -j` (no trailing newline) into the public-inputs commit.

The strip list is not hardcoded. It is the root-input difference between the fork `flake.lock` and
the public `flake.lock`, so it tracks whatever `flake-lock-merge` removed, whatever the inputs are
named.

---

## Post-update fixes

If a build fails, fix the files in `@` (the empty top), then place the fix on the correct chain.

### Choose the chain by content, not by the host that found it

**This is the rule to remember.** A fork host can surface a fault whose fix is entirely generic. A
generic module fix carries no private content, so it belongs on the **public** chain, below the
tree merge, and the fork chain inherits it through the merge. The obvious move — commit it on top
of `fork-tip` — puts a public fix on the private chain, where it never reaches the public remote.

Decide with the audit, not by intuition:

```bash
jj fork-audit -q --color=never '@'      # clean → the fix is public
```

- **audit clean** → public fix. Insert it after `upstream-tip` and before the tree merge.
- **audit flags it** → fork fix. Leave it above the merge on the fork chain.

Then check whether the tips are pushed, because that decides the method:

```bash
jj log -r 'fork-tip' --no-graph -T 'if(immutable, "PUSHED", "not pushed") ++ "\n"'
```

### Public fix, tips NOT pushed yet

```bash
jj split --insert-after upstream-tip --insert-before tree-merge \
  -m 'fix(...): description' -- <public-files>
```

`--insert-after upstream-tip` places the new commit on the public chain. `--insert-before
tree-merge` re-parents the merge onto it. You need BOTH: `--insert-after` alone leaves the new
commit as a dangling sibling and does NOT re-parent the merge, so the fix would miss the fork
build. After the split, `@` stays the empty working copy on top of the fork chain.

Use `-B tree-merge`, not `-B fork-tip`, when a fork-only leaf sits above the merge — see the
warning in [step 4](#4-insert-the-public-inputs-commit).

This step rewrites the tree merge. That is fine while the merge is **mutable** (not pushed). Do
NOT do this after a push — see the next section.

`--insert-after`/`--insert-before` are the long forms of `-A`/`-B`. This is the mutable-tree
placement golden path; see [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md#golden-paths) and its proof
[test_placement.md](../checks/jj-experiments/test_placement.md).

### Public fix, tips ALREADY pushed

After `jj sync-remotes`, both tips are immutable. **NEVER rewrite a pushed commit.** Do NOT use
`--insert-before` on a pushed merge. Do NOT use `--ignore-immutable`. Both rewrite published
history and force a force-push.

Instead, extend both chains **forward** as fast-forwards, then add a **new merge commit** on top:

```bash
# @ holds the fix content:
jj describe -m 'fix(...): description'          # @ = the fix
jj rebase -r @ -d upstream-tip                  # fix now extends the upstream chain
FIX=$(jj log -r @ --no-graph -T 'change_id.short()')
# new merge on top: old fork merge + the fix — advances the fork chain forward:
jj new fork-tip "$FIX" -m 'chore(fork): merge <fix> from upstream'
jj new fork-tip                                 # park an empty single-parent @ for review
```

This build-forward pattern (never rewrite a pushed commit; add a new merge on top) is the frozen
pull-upstream golden path; see its proof [test_rebase.md](../checks/jj-experiments/test_rebase.md).

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

A **fork-specific** fix goes on the fork chain, above the merge — a plain
`jj split -m '...' -- <files>`, no insert flags needed.

If the target commit already exists on the correct chain, and you edit those same files again in
`@`, fold the new edits into that commit instead of making a new one:

```bash
jj squash --from @ --into <target-commit> -- <files>
```

`--from @` is the default, so `jj squash --into <target> -- <files>` is equivalent. Note `--into`
(`-t`) cannot combine with `-r`/`--revision`; use `--from`/`--into`.

Do NOT run `jj bookmark set` — `jj sync-remotes` moves the bookmarks after the topology is
correct. See [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for the graph surgery.

---

## Testing

Same as [flake-update.md](flake-update.md#testing), with the fork gates from
[step 8e](#8e-the-build-gates-and-their-order):

- The **NixOS** build of `upstream-tip` gates the **public** push.
- The **Darwin** build of `fork-tip` gates the **private** push.
- Darwin `switch` requires sudo — hand it to the user.
- You cannot build a NixOS host from the macOS machine. Use a NixOS host, or
  `./nixos-rebuild.sh build remote=<hostname>`.
