---
type: Rule
description: Summarizes the fork flake update workflow and points to the full doc and the skill.
timestamp: 2026-09-09T18:00:00+02:00
---

# Flake Update — Fork Workflow

Full doc: [../../docs/flake-update.fork.md](../../docs/flake-update.fork.md)

Base procedure: [flake-update.md](flake-update.md). Fork jj topology:
[../../docs/jujutsu-vcs.fork.md](../../docs/jujutsu-vcs.fork.md) — `jj fork-help` prints it.
For the command-by-command walk-through, use the `flake-update-fork` skill.

## Two rules that override everything

1. **NEVER move a bookmark by hand.** Do not run `jj bookmark set` for `main` or `upstream`.
   `jj sync-remotes` reads the topology and moves both: `upstream-tip` → `upstream`,
   `fork-tip` → `main`. You build the topology only. The user runs `jj sync-remotes` and pushes.
2. **`@` is a plain empty change with one parent.** It holds no content and never sits in the
   middle of the graph. `nix run '.#update'` writes the lock files into `@`, but that state is
   transient. Carve the content into a described commit at once, and keep `@` empty above it.
   One exception: after `jj sync-remotes` both tips are immutable, so you stack new work with
   `jj new fork-tip upstream-tip`. That is the only correct dual-parent `@`.

## Commit shape after a finished update

```
@                       empty working copy, single parent
○   fork merge          "chore(flake): update"                  full locks    ◄ fork-tip → main
├─╮
│ ○ upstream update     "chore(flake): update (public inputs)"  public locks  ◄ upstream-tip → upstream
◆ │ main@<fork-remote>
├─╮
│ ◆ upstream@<fork-remote>
```

- The **upstream update** holds the public inputs only, in `flake.lock` and `devenv.lock`. Patch
  file changes go there too. Its parent is the public tip.
- The **fork merge** holds all inputs. Its two parents are the upstream update and the fork
  `main`, so it sits directly on top of the upstream update. That link is the point of the shape.
- Both lock files get the same split. `flake-lock-merge` writes `flake.lock`. It cannot write
  `devenv.lock` — strip the fork nodes with `jq` (see the full doc).

## Quick sequence

```bash
# STEP 0 — fetch, then reconcile. Never skip this: every placement reads a remote-tracking ref.
jj git fetch --all-remotes
jj log -r 'upstream-incoming'    # must be empty before you go on
jj log -r 'fork-incoming'        # must be empty before you go on

# STEP 1 — name the start state. Only "empty 2" and a frozen-merge "empty 1" may start an update.
jj log -r '@' --no-graph -T 'if(empty,"empty","content") ++ " " ++ parents.len() ++ "\n"'
jj log -r 'to-rebase'                        # not empty → route or publish the stack first
jj log -r 'fork-leaked & ::upstream-safe'    # not empty → reorder first

# STEP 2 — update
nix run '.#update'
devenv update                    # devenv.lock uses a separate resolver — BOTH are required

# STEP 3 — carve the full locks onto the fork side:
jj split -m 'chore(flake): update' -- flake.lock devenv.lock .flake.patches/

# STEP 3b — a mutable merge MUST exist before the insert:
jj log -r 'tree-merge & mutable()' --no-graph -T '"exists\n"'
jj new --no-edit -B @ -m 'chore(upstream): merge'   # ONLY when the line above prints nothing

# STEP 4 — insert the public-only update — BOTH flags, one command:
jj new --insert-after upstream-tip --insert-before tree-merge -m 'chore(flake): update (public inputs)'

# STEP 5-7 — write the public-only locks (see the skill), move .flake.patches/ down, park @:
jj new fork-tip

# STEP 8 — prove the run is complete, then hand off. NEVER run `jj bookmark set`.
bash hack/flake-update-complete.sh
```

## Agent notes

- **Fetch first, and fetch again before the hand-off.** `nix run '.#update'` never fetches. The
  only built-in fetch runs inside `sync-upstream`, at push time — too late to change a placement.
- **A completion check is mandatory.** An incomplete run looks finished: the two tips already
  differ even when the public chain holds no update. Run `hack/flake-update-complete.sh`.
- **`-B tree-merge`, not `-B fork-tip`,** whenever a fork-only leaf sits above the merge.
  `fork-tip` is then that leaf, and `-B fork-tip` turns it into a merge.
- **The insert needs a mutable tree merge.** Check `tree-merge & mutable()` first; manufacture one
  with `jj new --no-edit -B @` when it is empty.
- **Never redirect into the file a `jj` read is reading.** The redirect truncates it before the
  read, and jj's snapshot carries the empty file to the descendants. Use a temporary file, then
  `mv`.
- **Choose the chain for a post-update fix by content, not by the host that found it.** A generic
  fix found on a fork host is public: insert it after `upstream-tip` and before the tree merge.
  Confirm with `jj fork-audit -q --color=never '@'`.
- **`jj fork-audit` with no revset scans both chains, so it normally exits 1 in a fork repo.**
  Pass an explicit revset (`'upstream-tip'`) and read the output; never read the bare exit code as
  a verdict.
- Pass `-m 'msg'` and `-- <files>` to `jj split`/`jj describe`/`jj squash`. They open an editor by
  default. `jj new` and `jj rebase` need no editor.
- Never use bare `upstream` in a revset. Use `upstream@<fork-remote>`, the stable anchor.
- The two pushes are not atomic and `sync-remotes` publishes the **public** chain first. Finish
  every check before the hand-off; the public push is not reversible.
