---
type: Design
description: Build an isolated pytest harness in checks/jj-experiments, verify golden-path jj recipes on facts for both fork/branch topology and day-to-day operations, finish the revset-alias suite, and rewrite the jj docs and skill to be short and teachable.
authored_by: agent
timestamp: 2026-09-02T00:00:00+02:00
---

# Design — jj fork change-placement: harness, matrix, docs

This design drives `docs/tasks/jj-fork-use-cases-refactor.md`. It also finishes
`docs/tasks/jj-fork-revset-pytest-suite.md`. It does not touch `docs/tasks/jj-fork-doctor.md`.

## Decisions (from the user)

1. The whole harness lives in `checks/jj-experiments/`.
2. Build the isolated harness first. Then work case by case. Test each recipe through the harness.
3. Pull context from the revset-suite task. Finish that task inside this work.
4. Generalize the model to a long-lived branch too. This is **in scope**. A fork and a long-lived
   branch are about 90% the same concept.
5. Persist this design in this `.design.md` file.

## Scope — two families of use-cases

This task covers two families. The golden-path and harness treatment applies to both.

- **Topology use-cases** — fork and long-lived-branch workflows: change placement, merges, pull
  upstream, frozen vs mutable tree. A fork and a long-lived branch are one model (decision 4);
  the fork is one mode of a branch workflow.
  - **Doc home is conditional on the Phase 2 finding.** If a topology case turns out to be the
    same as a plain branch case, describe it **primarily in the base `docs/jujutsu-vcs.md`**, and
    only **reference** it from `docs/jujutsu-vcs.fork.md`. The fork doc then keeps only the
    genuinely fork-specific parts: the fork and upstream remotes, sensitive-content routing
    (`fork-direct`/`fork-leaked`), and `sync-remotes`. It does not repeat a case that the base doc
    already covers.
  - Only a case that is truly fork-only (no plain-branch equivalent) stays described in the fork
    doc itself.
- **Day-to-day use-cases** — common jj operations every developer runs, branch-agnostic: squash
  vs `jj absorb`, split, describe, move hunks between commits, undo and the operation log, and
  working-copy hygiene. These land in the base `docs/jujutsu-vcs.md` and the base skill.

The harness covers both families. Day-to-day cases need no fork remotes; they use a single repo
from `mkrepo`. Topology cases use the three-repo fixtures.

## Guiding principle — one golden path per use-case

The main goal is a single **golden path** for each use-case: the sequence with the **least
cognitive load**. Prefer one simple command, or the shortest sequence a person can hold in the
head, over a clever multi-command recipe. The original skill grew complicated, multi-step recipes.
This work replaces them.

Method, per use-case: brainstorm several candidate sequences, run each through the harness, then
pick the one that is simplest to remember and hardest to get wrong — not only the fewest commands.
The verified unified recipe (below) is one example of the target bar: two plain commands that work
on both a frozen and a mutable tree, with no `-r` targeting and no manual rebase. Aim for that
level of simplicity in every case.

### Teachable, human-first commands

The agent must be able to **teach** the user jj while it works. So a golden path uses
human-first, low-cognitive-load commands that the agent can explain in one line each. Prefer a
plain, self-explaining command over a cryptic revset trick when both reach the same state. A
developer should learn the pattern by watching the agent run it.

This applies to three places:

- **Golden paths (docs).** Each step names what it does in plain words. Avoid deep revset
  gymnastics unless the named alias makes the step clearer, not harder.
- **The harness (living reference).** Each test reads as a worked example. It carries a docstring
  that states the scenario and the golden path in plain words. It uses the same human-first
  commands the docs recommend, so a developer opens a test to learn the pattern. The tests are
  reference material first, assertions second.
- **The skill (shortest possible).** The result must make the skill **as short as possible**. The
  skill lists only the golden path per case, in a compact form. For advanced reasoning — why a
  path works, the frozen-vs-mutable detail, edge cases — the skill **links to the docs and the
  harness tests** instead of explaining inline.

## Key research findings (verified)

### The task premise is only half correct

The task says `-A`/`-B` "fail on a frozen (pushed) tree-merge". Empirical test (jj 0.44.0) shows:

- `jj split -A <frozen>` **succeeds**. It appends a new child after the frozen commit. It
  re-parents only the **mutable** descendants. It never rewrites the frozen commit.
- A command fails **only when it must rewrite the frozen commit itself** — for example
  `-B <frozen>` (the frozen commit must move), or a `rebase`/`describe` on the immutable set.

Correct rule: insert-after a frozen tip is legal. Any placement that reparents or rewrites the
frozen commit is not. The harness pins down which case is which.

### Verified unified recipe (frozen and mutable trees)

A two-command sequence places generic content on the upstream chain on a **frozen** tree without
any immutable error (verified, jj 0.44.0, real bare remotes):

```sh
jj new --no-edit -B @ -m 'chore(upstream): merge'
jj split -m 'feat(...): generic' -A upstream-tip -B fork-tip -- <generic files>
```

- Command 1 inserts a mutable described commit `N` between the frozen merge `M` and `@`. `M` stays
  untouched. `N` becomes the new `fork-tip` (it is the newest described fork-chain commit).
- Command 2 grafts the generic content as commit `S`, a single-parent, content-clean child of
  `upstream-tip`, so `S` is on the upstream chain (not tagged `fork`). It turns `N` into
  `merge(M, S)`. `M` stays a parent, so the frozen history stays an ancestor and `sync-remotes`
  fast-forwards. No immutable commit is rewritten. `tree-merge` moves to `N`; `to-rebase` and
  `fork-leaked` end empty.

This is cleaner than the earlier frozen recipe `jj new fork-tip upstream-tip` + split, which
creates a redundant `{M, upstream-tip}` edge, strands `@`'s content in an orphan commit, and needs
extra `-r` surgery. Because command 1 always makes `fork-tip` mutable, the same form works on a
mutable tree too. Candidate for **the** recommended recipe. Phase 2 confirms it across the matrix.

### jj 0.44.0 flag semantics (empirical)

- `-A`/`--insert-after` and `-B`/`--insert-before`: **re-parent** the anchor's descendants.
- `-d`/`-o`/`--destination`: set **only** the new commit's parents. No re-parent.
- Two **sibling** anchors (`-A x -A y`) create a real 2-parent merge. Two anchors where one is an
  ancestor of the other fail with a loop error. `-A a -B b` on a linear chain collapses to a
  single parent (same slot).
- `jj new a b` builds a merge with parents a and b.
- `jj rebase -s 'roots(<set>)' -d <dest>` moves a subtree.
- String pattern gotcha: bare `description(B)` does not resolve. Use bookmarks or
  `description(substring:"B")`.

### Immutability

- A pushed bookmark that is **tracked** is not immutable by default.
- Immutability needs `trunk() = main@<fork-remote>` (this repo's alias) plus the pushed bookmark,
  OR the config alias `revset-aliases."immutable_heads()"`. There is **no** `revsets.immutable-heads`
  key.
- Chicken-and-egg trap: an alias that names a not-yet-existing bookmark breaks **every** jj
  command. Apply such an alias only after the ref exists, or wrap it as `present(<ref>)`.
- Verbatim immutable error starts with `Error: Commit <id> is immutable`.

### Bare-remote push/fetch

- `git init --bare` + `jj git remote add` + `jj bookmark set` + `jj git push`/`fetch` works
  headless between local dirs. No auth.
- No `--allow-new` flag in 0.44. `jj git push --bookmark <name>` auto-tracks a new bookmark.
- A colocated repo exposes local git refs under a pseudo-remote named `git` (for example
  `main@git`).

### Complete `$HOME` isolation (confirmed set)

```sh
export HOME=<tmp>/home
export XDG_CONFIG_HOME=<tmp>/xcfg
export XDG_DATA_HOME=<tmp>/xdata
export XDG_STATE_HOME=<tmp>/xstate
export XDG_CACHE_HOME=<tmp>/xcache
export JJ_CONFIG=<tmp>/jj.toml        # holds [user] name/email + any knobs
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
```

- `JJ_CONFIG` fully overrides the XDG search for the user config file.
- jj keeps its operation log and working state in `.jj/` (repo-local), not under `$HOME`.
- Bake `user.name`/`user.email` into `JJ_CONFIG` up front. Do not use `jj config set` after `@`
  exists.

### Slot wiring (how to get the real fork aliases)

- `mkSlots`/`renderTarget` (`lib/slots/default.nix:30-42`) exposes a read-only `slots` option that
  carries the full evaluated slot config. `devenv eval 'slots.kdn.jj.config'` returns the whole
  rendered jj config, all aliases included.
- `devenv eval` takes an attr-path. It chokes on a quoted hyphenated sub-path. Read the parent
  attr and index in Python.
- The base jj slot applies config by an `enterShell` symlink into `jj config path --repo`
  (`.jj/repo/config.toml`), pointing at the generated TOML. The harness reproduces this.
- The alias strings **bake in** `fork.remote` and `upstream.remote` at eval time. `fork.remote`
  defaults to `""`. The harness must set `kdn.jj.fork.{enable,remote}`, `upstream.remote`, and
  `deniedFilePatterns`, and name the fixture remotes to match.
- Use `path:../..` for the self-reference, not `git+file:`. `git+file:` reads git's index and
  misses uncommitted/untracked fixtures. jj colocation makes the index unreliable.

### Nix sandbox can create jj repos

- The `kdn-slug` check proves it: `runCommand` with `jujutsu`+`git`+`python3-pytest` on
  `nativeBuildInputs` and `HOME=$(mktemp -d)`. Reuse this pattern.
- The sandbox cannot run `devenv eval`. So the check must bake the rendered TOML in as a build
  input. The interactive shell reads it live.

### Reference topology (from the revset-suite research)

Node list (label : parents : content : bookmarks). Post-fetch, resting single-parent `@`.

- `A` — root. `README.md`. Ancestor of all remotes.
- `P1` — parent A. Generic (`flake.lock` v1). Public upstream history.
- `P2` — parent P1. Generic (`flake.lock` v2). `main@<upstream>` here. Fetched, not merged.
- `U1` — parent A. Generic (`modules/shared.nix`). Local upstream-side, described.
- `U2` — parent U1. Generic edit. Described. Local `upstream` + `upstream@<fork>`. (upstream-tip)
- `F1` — parent A. Fork-sensitive path. Described. Fork-chain.
- `M` — parents U2 and F1. Merge `chore(merge): merge in upstream`. Local `main` + `main@<fork>`.
  (tree-merge)
- `L1` — parent M. Generic (`modules/foo.nix`). → upstream-safe, not leaked.
- `L2` — parent L1. Fork-sensitive. → fork-leaked, not safe.
- `L3` — parent L2. Generic. → upstream-safe.
- `@` — parent L3. Empty, no description.

Expected sets: `tree-merge`={M}; `upstream-incoming`={P1,P2}, tip P2; `to-rebase`={L1,L2,L3};
`fork-direct`={F1,L2}; `upstream-safe`={L1,L3}; `fork-leaked`={L2}; `upstream-local`={U1,U2};
`pushed`={A,P1,P2,U1,U2,F1,M}; `pushed-fork`={A,U1,U2,F1,M}; `pushed-upstream`={A,P1,P2};
`merge-frozen`={M} when M is pushed as `main@<fork>` (empty variant: build merge unpushed).
`fork` tags all descendants of `main@<fork>`, so `to-rebase & ~fork` = ∅ (the trap). Therefore
`upstream-safe` uses `~fork-direct`, not `~fork`.

Requirements the fixtures must honor: deterministic monotonic commit dates (because `latest()` is
timestamp-based); `fork-tip` is the topmost described local commit once local work exists (L3, not
F1).

### fork-direct content patterns

`fork-direct` matches a case-insensitive substring in a path, a diff line, or a description,
driven by `deniedFilePatterns`/`deniedMessagePatterns`. The harness uses placeholders such as
`PLACEHOLDER-SENSITIVE` and `PLACEHOLDER-PREFIX-`. No real sensitive term goes anywhere in this
work.

### sync bookmark moves (to simulate post-sync)

After a full `sync-remotes`: local `upstream`=upstream-tip; `main@<upstream>`=upstream-tip;
`upstream@<fork>`=upstream-tip; local `main`=fork-tip; `main@<fork>`=fork-tip. The harness runs the
bookmark/push commands directly and skips the interactive prompt.

### Reliability signal from session history (atuin vs transcripts)

A correlation of the human's atuin history (2882 jj runs, with exit codes) against the agent
transcripts (413 jj calls) overturns the naive "agent breaks it, human repairs" model:

- Agent jj usage is broadly **reliable** — including risky fork merges and rebases with lockfile
  conflicts (2026-08-24, 08-26, 08-28), which the agent resolved and the human did not repair.
- The human's `undo`/`abandon` clusters follow the human's own interactive experimentation, not
  agent mutations.
- So the golden-path work encodes the **few real failure modes** as guardrails. It does not spray
  caution everywhere.

Real failure modes to encode (verified from history):

- **Never open an editor non-interactively.** One real failure: an agent `describe`/`restore`
  without `-m` opened `hx` and exited 101 (08-26). Every `describe`/`split`/`squash` passes
  `-m 'msg'`; set `JJ_EDITOR=true` for a `split` file-selection step.
- **Squash form.** Use `jj squash --from <src> --into <dst> -- <files>`. Never `jj squash -r @
  --into` (mutually exclusive flags — a real error, 08-07).
- **On a fork update, do not hand-place bookmarks.** The human's worst thrash — repeated `jj undo`
  of their own placement (08-04, 08-07) — was manual bookmark placement. Run one placed
  `jj split -A upstream-tip -B fork-tip -m '…' -- <files>` and let `jj sync-remotes` set the
  bookmarks.
- **The human drives the fork merge.** 7 of 18 flagged agent mutations were the human rejecting the
  tool call at the permission prompt — mostly the 08-07 fork-merge steps (`describe`,
  `new fork-tip upstream-tip`, placed `split`). The agent proposes; it does not push or set the
  release bookmarks.

Recovery golden path (what the human actually uses): `jj undo` first (56 uses, single-step
reversal); `jj op log` + `jj op restore` for a multi-step backout.

Phase 2 prioritizes the NEEDS-CARE areas — bookmark and sync placement, the squash flag form, and
the editor guard — for explicit harness proof.

## Harness architecture

### Isolation base

A per-test fixture builds a tmp root and exports the confirmed isolation set. It writes the
`JJ_CONFIG` file with `user.name`/`user.email` up front. All repos and bare remotes for one test
live under that tmp root. The fixture deletes the tmp root on exit.

### `mkrepo` fixture and `Repo` wrapper

`mkrepo` is a factory fixture. It returns a callable that creates repos. It remembers every repo
it creates. It deletes them on exit through a `try: ... finally: ...` context-manager style. Each
repo shares the test's isolated env.

`Repo` is a dataclass wrapper:

- `.path` — the repo directory path.
- `.jj(*args)` — run a jj command in the repo with the isolated env. Return the result.
- `.cfg` — a `JJConfig` builder (below). `.cfg.apply()` writes the merged config into the repo.
- `.register_remote(name, definition)` — add a remote. The `definition` names a bare repo (a path
  or another `Repo`). The helper creates the bare repo when needed and runs `jj git remote add`.
- Extra helpers as needed: `.log_graph()`, `.change_id(label)`, and a small commit/write helper
  with a fixed date.

### `JJConfig` layered dict builder

A dict-backed config with deep-merge overlays. Later layers win.

- `from_slot(toml)` starts from the rendered fork aliases. `without_slot()` starts empty for a
  pure experiment.
- `revset_alias(name, expr)`, `alias(name, argv_list)`, `set("ui.color", "never")` (dotted path),
  `merge({...})` for a whole section.
- Two apply points: at repo init, and again after the topology exists. This avoids the
  not-yet-existing-ref trap for `trunk()`/`immutable_heads()`.

The builder renders to the repo-scoped `.jj/repo/config.toml` (matches the slot). The isolation
layer (user, git config off) always stays underneath.

### Two run modes, one test file

- Headless check: `checks/default.nix` generates the fork TOML from the slot
  (`lib.kdn.mkSlots` → `.config.kdn.jj.config` → `pkgs.formats.toml`). It passes the store path as
  `JJ_FORK_CONFIG_TOML` into a `runCommand` (jujutsu+git+python3-pytest, `HOME=$(mktemp -d)`), like
  `kdn-slug`. Run one check: `nix build .#checks.<system>.jj-experiments-pytest`.
- Interactive: `checks/jj-experiments/devenv.{yaml,nix}` with `inputs.nix-configs.url =
  "path:../.."` and a `mkSlots { kdn.jj.fork.remote="fork"; upstream.remote="upstream";
  deniedFilePatterns=["PLACEHOLDER-SENSITIVE" ...]; }` import. `devenv shell`, then
  `pytest -k <case>`.

The test reads the aliases from `JJ_FORK_CONFIG_TOML` in both modes. The test file is the same in
both modes.

### Experiment ergonomics

A throwaway experiment is a few lines: get a repo from `mkrepo` or a topology fixture, tweak
`.cfg` with the one-line shortcuts, `.cfg.apply()`, run a jj sequence with `.jj(...)`, assert
`.log_graph()`. Add or delete the test function freely.

### Harness layout — grouped tests paired with docs

Group the use-case tests by family into their own pytest files. Pair each test file with a
sibling `.md` file that explains the cases in more detail and references the tests that
demonstrate each caveat. So the tests are the executable examples, and the `.md` is the prose that
points at them.

Layout under `checks/jj-experiments/`:

- `conftest.py` — isolation base, `mkrepo`, `Repo`, `JJConfig`, shared helpers.
- `test_<group>.py` — one file per use-case family (for example `test_placement.py`,
  `test_squash_absorb.py`, `test_rebase.py`, `test_revsets.py`).
- `<group>.md` — the detailed explanation for that family. It states each case and its golden
  path, and links to the specific test functions (by name) that prove the caveats.

This makes a three-tier reference:

- **Skill** — shortest form, golden path per case, links out.
- **Base `docs/jujutsu-vcs.md`** — concise golden paths plus the consolidated matrix, the primary
  home; links to the group `.md` files and the tests.
- **`checks/jj-experiments/<group>.md` + `test_<group>.py`** — the detailed prose and the
  executable proof of every caveat.

Each `.md` file carries OKF frontmatter (`type:`) and follows Simple Technical English.

### Starter topology fixtures

Built on `mkrepo`:

- `full_reference` — the node list above, with real bare `upstream` and `fork` remotes and pushed
  bookmarks. Exercises every revset alias at once.
- `frozen_tree` — merge pushed to the fork remote (`merge-frozen` non-empty; immutable via
  `trunk()`).
- `mutable_tree` — the same shape with the merge unpushed (`merge-frozen` empty).
- `mixed_working_copy` — `@` holds mixed generic + fork-sensitive content, ready to split.

Each fixture returns the repo handle plus a label→change-id map.

### Long-lived-branch generalization (in scope)

A fork and a long-lived branch share the same shape. The only fork-specific parts are `trunk()`
and the remote names. Design:

- Give the topology fixtures a `mode` axis: `fork` (trunk = `main@<fork>`) and `branch`
  (trunk = the branch base on one remote).
- The `JJConfig` builder supplies a branch-mode alias overlay for the `branch` fixtures. This does
  not need a slot change to prove the model; the arbitrary-config capability covers it.
- Decide during Phase 2 whether the slot needs new options for branch mode, or whether the doc
  frames both modes over the existing fork slot. Record the decision in the task `.done.md`.

## Use-case catalog (for exploration)

This catalog lists every use-case to explore in Phase 2. It has three in-scope categories plus one
out-of-scope group. Treat each item as a candidate. Phase 2 confirms each on facts and picks a
golden path.

### Category 1 — Topology (fork and long-lived branch)

From the task matrix:

- Immutable tree: upstream change; fork change; mixed `@` split by content; make the tree mutable
  with a new merge, then act; make the tree mutable by adding a fork change.
- Mutable tree: upstream change; fork change; mixed change; squash updates into an existing mutable
  commit.
- Task candidate cases: fork change that depends on a new upstream commit (X→Y, both tree states);
  a partly-generic, partly-sensitive change (`fork-leaked` handling); amend or reword an
  already-pushed commit (expected: forbidden, build forward); multiple stacked upstream commits;
  abandon a not-yet-pushed change; pull in new upstream while local generic + fork work sits above
  the merge; squash into an immutable commit (expected: forbidden).

Added candidates:

- The verified unified recipe as the single golden path for both frozen and mutable trees.
- Place a generic commit between `upstream-tip` and an existing **mutable merge** in one command:
  `jj split -A upstream-tip -B fork-tip -m '…' -- <files>` (here `fork-tip` is the merge; `-B`
  reparents the mutable merge onto the new commit; no follow-up rebase). This is the mutable-tree
  case of the verified unified recipe — you skip the `jj new -B @` merge-shell step because the
  mutable merge already sits in the middle. Confirmed live on 2026-09-02. Harness must cover it and
  contrast it with the frozen-tree case (where `-B fork-tip` on a frozen merge would fail).
- Reorder two independent local changes above the merge.
- De-leak a change: reword or split a `fork-leaked` commit into a safe part and a fork part.
- Split an already-committed mixed change (`jj split -r <id>`).
- `upstream-incoming` that conflicts with local upstream work on rebase.
- Fork-side work that must rebase when new upstream is pulled in.
- `latest()` timestamp hazard: `upstream-tip`/`fork-tip` resolve wrong; detect and fix.
- Restore the dual-parent `@` after publish; never `describe` a dual-parent `@`.

### Category 2 — Day-to-day operations (branch-agnostic, single repo)

Grounded in the atuin frequency scan (`log` 196, `split` 123, `diff` 105, `rebase` 105, `new` 67,
`bookmark` 62, `squash` 42, `edit` 42, `abandon` 41, `describe` 30, `restore` 7, `absorb` 3, …).
Note: `rebase`, `edit`, and `abandon` are heavy in real use, though the base doc frames `rebase`
as a last resort and `jj edit` only as "do not read a file with it". Reconcile the docs — give
these clean golden paths, not warnings.

- Inspect / read: `jj diff -r <id>`, `jj diff --from X --to Y`, `jj show <id>`, `jj st -r <rev>`,
  `jj log` idioms, `jj file show`; add `--no-pager` for agents.
- Amend / rework a commit: amend in place (`jj edit <id>` → change → `jj new`) versus accumulate in
  `@` then `jj squash --into <id>`; `jj describe`/reword; split `@`; split `-r <id>`;
  `jj diffedit -r <id>` (human, interactive); squash versus `jj absorb` (needs verification).
- Move / restructure: `rebase` intents — move one change (`-r <id> -d <dest>`), move a stack
  (`-s`), reorder siblings, restack after an insert or abandon; `jj abandon <id>` and the
  descendant rebase; `jj duplicate <id> -d <dest>` (cherry-pick); `jj simplify-parents` to drop a
  redundant merge edge; `jj revert`.
- Discard / recover: `jj restore <paths>` and `jj restore --from <rev> <paths>`; undo and the
  operation log (`jj op log`, `jj undo`, `jj op restore <op>`); discard all `@` changes.
- Sync & bookmarks: `jj git fetch --all-remotes` then bring `@` current; `jj git push -b <name>`;
  bookmark verbs `set`/`create`/`move`/`delete`; `jj bookmark list --all-remotes`.
- Repo hygiene: `jj untrack '<glob>'` and the `.gitignore` interplay; clean a stale
  `.git/index.lock` (colocation artifact).
- Conflicts: detect with `jj log -r 'conflicts()'`; resolve (human `jj resolve`; an agent edits
  the markers and jj then clears the conflict).

### Category 3 — Advanced / agent-centric use-cases

Mined from 27 past session transcripts (969 jj occurrences). These are the analytical, agent-driven
idioms above the day-to-day verbs. Most build on the repo's custom revset-alias vocabulary
(`fork*`, `upstream*`, `tree-merge`, `to-rebase`, `pushed*`, `merge-frozen`, `trunk()`). The
harness must cover these too: assert each idiom returns the expected set on a known topology, and
record each as a documented analysis idiom. Sensitive names stay placeholders.

**Revset / tree-graph analysis (the dominant category).**

- Fork-graph overview — render the whole stack (trunk to tips, working copy, bookmarks) in one
  template:
  ```
  jj log -r 'trunk()..(@ | heads(trunk()..))' -T '<change-id + flags + bookmarks + subject>'
  ```
- Reachability membership idiom — intersect a change with `::<target>` and read emptiness as a
  verdict. This is the agent's core boolean tool:
  ```
  jj log -r '<rev> & ::main@<upstream-remote>'   # non-empty = already published upstream
  jj log -r 'main@<upstream-remote> & ::<rev>'   # empty = <rev> is NOT an ancestor, so diverged
  jj log -r '<rev> & ::upstream-incoming-tip'    # non-empty = redundant after the rebase
  ```
- Reusable-vs-frozen merge check: `tree-merge & (immutable() | pushed)` (empty = reuse the merge)
  and `tree-merge & mutable()`.
- Roots of a subgraph for a `rebase -s`: `roots(to-rebase)`,
  `roots(pushed-upstream..(::tree-merge & ~fork))`.
- Scope sets: `conflicts()` (clean-or-dirty gate), `mutable()` (rewritable), `mine()` (own
  authorship).
- File history: `::<branch> & files("<path>")` — where a file was introduced or edited.
- Parent introspection template — confirm a merge's two parents:
  ```
  jj log -r 'tree-merge' -T '... parents.map(|p| p.change_id().shortest(8) ++ "(" ++ p.bookmarks() ++ ")") ...'
  ```
- Identity probe: `latest(A..B) ~ B` empty = A and B are the same commit.
- Description-filtered ancestry: `::@ & description(<keyword>)`; skip empties with `~empty()`.

**Topology surgery.**

- Placed split into a graph edge, no follow-up rebase:
  `jj split -A upstream-tip -B fork-tip -- <files>` (`JJ_EDITOR=true` for non-interactive).
- Placed rebase or new: `jj rebase -r <rev> --insert-after X --insert-before Y`;
  `jj new --insert-after upstream-tip --insert-before fork-tip -m '...'`.
- Subtree rebase by revset: `jj rebase -s 'roots(to-rebase)' -d upstream-tip`.
- Build or rebuild the dual-parent merge: `jj new fork-tip upstream-tip`, `jj new -d main -d
  upstream`.
- Repoint or de-duplicate merge parents: `jj rebase -r <merge> -d P1 -d P2`;
  `jj simplify-parents -r <rev>`.
- Placed squash to a named target with a pathspec: `jj squash --from @ --into <rev> -- <files>`.
- File-level restore across changes: `jj restore --from <rev> <file>`.

**Operation-log forensics and recovery.**

- Compact op history with a time-relative template, then roll back:
  ```
  jj op log --no-pager --limit 12 -T 'self.id().short() ++ " " ++ self.description() ++ " (" ++ self.time().end().ago() ++ ")\n"'
  jj op restore <op-id>   # or: jj undo
  ```

**Divergent / conflict handling.**

- `jj resolve --list [-r <rev>]`; tag conflicted ancestors in a log template with
  `if(conflict, ...)`; gate progress on `conflicts()` being empty. Real divergent-change resolution
  was not exercised (see gaps).

**Colocation / git-interop checks.**

- `jj bookmark list --all-remotes` cross-checked against `git remote -v`; `git ls-files -- <path>`
  to confirm tracked files (read-only git only).

**Content inspection across revisions (heavy).**

- `jj file show -r <rev> <path>` used as a read-only cross-revision diff engine, piped through
  `jq --sort-keys` / `diff` / `grep -c` to compare lockfiles between tips with no checkout. This is
  the agent's substitute for the forbidden `jj edit`-then-read.

**Introspection / config.**

- Discover repo aliases before composing a revset: `jj config list --repo | grep -iE
  'revset-aliases|aliases'`; `jj config get aliases.<name>`.
- Probe flag availability before a rewrite: `jj rebase --help | grep -i immutable`;
  `jj split --help | grep -iE 'insert|destination'`.

**Gaps to scope honestly (not exercised in history, so not golden paths here).** `--at-operation` /
`jj op diff` / `jj op show`, `jj evolog`, `jj interdiff`, `jj file annotate`, `jj duplicate`, real
divergent-change (duplicate change-id) resolution, and the workspace commands (out of scope above).
Cover them only when a real need appears.

### Out of scope for now — workspace and parallel work

Not covered by a golden path in this task: `jj workspace add` (sibling directory), `workspace
list`, `workspace forget`, `workspace update-stale`, and parallel isolated work. Keep the existing
hazard guidance in the base doc. Revisit later.

## Phases

### Phase 0 — Isolated harness foundation

- Create `checks/jj-experiments/` with `conftest.py` (isolation base, `mkrepo`, `Repo`,
  `JJConfig`), `devenv.yaml` (`path:../..`), `devenv.nix` (`mkSlots` with fork options set to the
  fixture remote names and placeholder patterns).
- Wire the check in `checks/default.nix` (generate TOML, pass `JJ_FORK_CONFIG_TOML`, `runCommand`
  pytest). Add a package or inline derivation like `kdn-slug`.
- Verify: `nix build .#checks.<system>.jj-experiments-pytest` runs a smoke test. `devenv shell`
  in the subdir runs `pytest -k smoke`.

### Phase 1 — Topology fixtures and revset-suite completion

- Build `full_reference`, `frozen_tree`, `mutable_tree`, `mixed_working_copy`.
- Assert every revset alias resolves to the expected set. Assert the `~fork` trap and the
  `~fork-direct` fix. Assert the post-sync bookmark state.
- Mark `docs/tasks/jj-fork-revset-pytest-suite.md` done. Add its `.done.md`.

### Phase 2 — Brainstorm the golden path per use-case

Work case by case (cases 1–9 plus the candidate-missing cases in the task, plus the extra
candidates below). For each case:

- Brainstorm several candidate sequences (not just one). Keep the golden-path bar in mind: least
  cognitive load, fewest surprising steps.
- Run each candidate through the harness. Build the required state (mutable or frozen), run the
  sequence, assert the graph and the post-conditions: `fork-leaked` empty, old tips stay ancestors
  so `sync-remotes` fast-forwards, no immutable rewrite.
- Pick one golden path per case — the simplest to remember and hardest to get wrong. Record the
  runner-up only when it is needed for a distinct sub-case.
- Use the reframed `-A`/`-B`-vs-frozen rule and the verified unified recipe as the starting bar.
- Cover both `fork` and `branch` modes where the golden path differs.

The full set to explore is in the [Use-case catalog](#use-case-catalog-for-exploration) below.
Work through it category by category.

`jj absorb` verification (required before recommending it over `jj squash`): the harness confirms,
on facts, where `jj absorb` routes each hunk. Cover: (a) hunks that each belong to a different
ancestor land in the correct ancestor; (b) a hunk with no clear ancestor stays in place; (c)
`jj absorb` refuses to move a hunk into an immutable ancestor; (d) confirm the exact flags and
their meaning (do not assume `-t`/`--into`; verify against `jj absorb --help` in the harness). Only
after these pass does a golden path use `jj absorb` on the user's behalf.

### Phase 3 — Docs and skill rewrite

- Base `docs/jujutsu-vcs.md` is the **primary home**. Put every golden path that has a plain-branch
  form here: the day-to-day cases (squash vs `jj absorb`, split, describe, undo, working-copy
  hygiene) and every topology case that Phase 2 shows is a plain branch case. Add the consolidated
  matrix here.
- Shrink `docs/jujutsu-vcs.fork.md` to a reference layer. It **links** to the base doc for the
  shared cases and describes only the fork-specific parts: fork and upstream remotes,
  sensitive-content routing (`fork-direct`/`fork-leaked`), and `sync-remotes`. Reconcile
  `docs/flake-update.fork.md`. It does not repeat a case the base doc covers.
- Make `.agents/skills/jujutsu-vcs/SKILL.md` (the source, not the installed copy) **as short as
  possible**. List only the golden path per case (both families) in a compact form. For the "why",
  the frozen-vs-mutable detail, and edge cases, link out to `docs/jujutsu-vcs.md`,
  `docs/jujutsu-vcs.fork.md`, and the named harness tests. Do not explain the reasoning inline.
- Revert or rewrite the wrong uncommitted `-A/-B, never -d/-o` edits.
- Delete the obsolete memory TODO `project_jj_split_placement_docs.md` and its `MEMORY.md` line.
- Frame fork and long-lived branch as one model.

### Wrap-up

- Flip `docs/tasks/jj-fork-use-cases-refactor.md` to `status: done`. Add its `.done.md`
  (Root cause, Solution, Verification, Follow-up). Keep this `.design.md` as the retained design
  and philosophy reference (the harness README, the skill, and the jj-expert agent link to it).

## Constraints

- Simple Technical English for all doc prose, code comments, and chat.
- All content is generic tooling, tests, and docs. It lands on the upstream chain. `fork-leaked`
  stays empty. Use placeholder patterns only. No sensitive term anywhere.
- Never push. The user runs `jj sync-remotes`. Never rewrite a pushed or immutable commit.
- Split commits by content. Leave an empty `@` only at wrap-up.
- Run jj experiments only in the isolated harness or under `/tmp`. Never run experimental jj in
  this repo (colocation hazard).
