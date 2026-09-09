---
type: Reference
description: Practical jj (Jujutsu) version control patterns and conventions used in this repo.
timestamp: 2026-07-31T14:00:00+02:00
---

# Jujutsu (jj) VCS

> **Agent summary:** [.agents/rules/jujutsu-vcs.md](../.agents/rules/jujutsu-vcs.md)

Practical patterns for this repo. See also the `jujutsu-vcs` skill for a mid-depth command
reference, the `jj-expert` subagent for deep troubleshooting,
[jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for fork-specific topology, and
[flake-update.md](flake-update.md) for the concrete update workflow that uses these patterns.

## Why jj, not git

This repo is jj-managed (colocated with git). Always use `jj`, never raw `git`, with two
exceptions: `git push*` and read-only git commands (`log`/`diff`/`show`/`status`/`remote`/etc).
Everything else — commit, add, checkout, reset, rebase, merge, stash, fetch, cherry-pick,
branch/tag mutation — has a direct jj equivalent and must go through jj instead. This keeps jj's
model (mutable commits, change IDs, op log) authoritative. See the `jujutsu-vcs` rule for the
full mandate and the reason behind each exception.

---

## For git users — start here

New to jj? This primer maps your git model to jj. Read it once, then use the golden paths below.

### Change vs commit

- A jj **change** is a commit that keeps a stable **change ID** across rewrites. The **commit ID**
  changes when the content or metadata changes; the change ID does not. Use the change ID when you
  mean "this commit, across amendments".
- There is **no staging area** and **no branch checkout**. `@` is the commit you edit right now —
  an always-committed working tree that auto-snapshots your files on every `jj` command.

### Mutable vs immutable

jj rewrites a **mutable** commit freely (amend, rebase, split, squash). jj **refuses** to rewrite
an **immutable** commit. A commit is immutable when it is pushed, or when `immutable_heads()`
matches it — in this repo, anything reachable from `trunk()` or a remote bookmark. This is why
some `jj rebase` or `jj edit` commands stop with "would rewrite immutable commits".

### Why `@` stays empty (this repo)

`@` auto-snapshots your working files into whatever commit it points at. An empty tip means your
next edits do not silently change already-described work. If you edit while `@` is a described
commit, jj adds your changes to that commit on the next snapshot — that is the footgun the empty
tip avoids. Full convention:
[When to leave an empty change on top](#when-to-leave-an-empty-change-on-top).

### Bookmark vs branch

- A **bookmark** is jj's branch: a named pointer to a commit.
- A **tracked** bookmark has an upstream set (like `git branch --set-upstream-to`). A freshly
  **fetched** bookmark arrives **untracked** — like a `refs/remotes/…` ref you have not adopted.
  Adopt it with `jj bookmark track <name>@<remote>`.
- There is **no "detached HEAD"**: `@` is always a real commit.

### Revset cheatsheet (the six you need first)

| Revset | Meaning |
|---|---|
| `@` | the working copy |
| `@-` | the working copy's parent |
| `x::` | `x` and its descendants |
| `::x` | `x` and its ancestors |
| `x..y` | commits in `y` but not in `x` |
| `trunk()` / `mutable()` | the main-branch tip / all rewritable commits |

`x::` (descendants) is not the same as `x..` (a range). Do not confuse them.

### git → jj command map

| git | jj |
|---|---|
| `git status` | `jj status` |
| `git commit` / `--amend` | `jj describe` (message) · `jj commit` · amend: `jj edit <rev>` … edit … then `jj new <tip>` to return to an empty tip |
| `git checkout <branch>` / switch | `jj new <rev>` or `jj edit <rev>` — no checkout; you edit a commit directly |
| `git switch -c <name>` | `jj bookmark create <name>` |
| `git stash` | park: `jj new`; resume: `jj edit <parked>` (no separate stash/pop) |
| `git rebase` | `jj rebase -s/-b/-r <rev> -d <dest>` |
| `git cherry-pick` | `jj duplicate` |
| `git reset --hard` | `jj restore` (files) · `jj abandon` (whole commit) |
| `git revert` | `jj revert` |
| `git reflog` | `jj op log` + `jj undo` / `jj op restore` |
| `git push` | `jj git push` |

### Safe push checklist

> 1. `jj git fetch --remote=<remote>` — see the real remote state.
> 2. `jj rebase -b @ -d <branch>@<remote>` — put your work on top of the incoming tip.
> 3. `jj git push --dry-run` — if it prints "move sideways", STOP and reconcile.
> 4. To never risk the primary branch, push a feature or PR branch — `jj git push -c <rev>` or a
>    named bookmark — not `main`.
>
> Force-with-lease rejects a **pre-fetch** push, but a **post-fetch** bare push can clobber. The
> push worked example is [test_push.md](../checks/jj-experiments/test_push.md).

**"Never push" (the repo rule) is for agents.** The push recipes here are for the maintainer to
run.

For the full command set see the [golden-path index](#golden-path-index); for the fork topology
see [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md); for worked, tested examples see
`checks/jj-experiments/test_<group>.md`.

---

## The working copy (@)

`@` is your scratch space: an unnamed change where edits accumulate. Unlike git's staging area,
there is nothing to "add" — `@` auto-snapshots on every `jj` command. An empty `@` (unnamed, no
content) once you are done is a **manual convention in this repo**, not something jj enforces or
automates. `jj describe` labels `@` with a message. `@` is now that named, non-empty commit — jj
does not create a new empty change on top for you. Only certain commands that split content off
`@` (see below) leave a fresh commit behind. That is inherent to how they partition a change, not
a general auto-refresh.

```bash
# accumulate edits in @, then carve out what is done:
jj split -m 'feat(...): description' -- path/to/file
# the *remaining* (non-selected) changes stay in @; the selected changes become a new
# commit as @'s parent
```

### When to leave an empty change on top

The empty change on top is a **wrap-up** step, not a checkpoint or a container.

- Run `jj new` to leave an empty `@` **only when you finish described work**. It gives the user a
  clean working copy to review from.
- Do NOT stack an empty change **above** undescribed or parked work. That buries the working copy
  one level down. When you park work, keep `@` on the parked change itself.
- Do NOT create an undescribed change in the middle of the graph as a checkpoint or a container.
  `jj split` already creates the follow-on change for you; you do not add one by hand.
- An empty `@` with no description is correct **only at the tip**, after the described work below
  it is complete.

### Preferred flow: accumulate, then carve

**Never create a new commit before you make changes.** Let edits accumulate in `@`, then:

- Use `jj split -- <files>` to carve part of `@` into a new named commit (accepts multiple
  `-- path1 path2 ...`).
- Use `jj squash --from @ --into <target>` to fold `@` into an existing mutable commit.

```bash
# wrong: create a commit up front, then wrestle to fix topology
jj new upstream -m 'feat: thing'
# ...make changes...

# right: make changes in @, then split/squash into the right place
# ...make changes in @...
jj split -m 'feat: thing' -- path/to/file          # carve off into a new named commit
jj squash --from @ --into <change-id> -m 'msg'     # fold into an existing commit
```

**`jj rebase` and `jj edit` are normal, safe tools — on mutable commits.** Use `jj rebase` to
reorder or restack local work, and `jj edit` to amend a commit in place. The one hard rule: never
rewrite a **pushed or immutable** commit — jj refuses it, so build forward instead (revert-forward;
see the day-to-day golden paths below and the fork forbidden cases). Prefer `jj split`/`jj squash`
for routine carving of `@`; reach for `jj rebase` when the graph shape itself must change (reorder,
restack, or construct a merge with `jj new <a> <b>`).

---

## Colocation hazard: `nix build/eval '.#...'` can see stale content

**A new or modified file can be invisible to `nix build`/`nix eval '.#...'` and to a real host
switch, even though `jj status` and `git status` both show it.** This is a real, confirmed
footgun. Verify with `git ls-files -- <path>` before you trust a build that touches a just-edited
file, when that build goes through the flake's own `self` (host configs, `darwinConfigurations`,
`nixosConfigurations` — anything reached via the CLI's `.#` shorthand).

**Mechanism, precisely:** this repo pulls in its own source tree through the `git+file://`
fetcher in both self-reference paths, so both behave the same way:

- `devenv.yaml`'s `nix-configs: url: git+file:.` (used by `modules/slots/*/default.nix`'s
  `inputs.nix-configs` self-references, and by devenv builds in general). It was `path:.` until
  commit `d2f3e8f8` (2026-07-31) switched it to `git+file:.`.
- `flake.nix`'s `nix-configs = self` (used by `kdnMetaModule`, and by `self` itself whenever the
  CLI resolves a local flake via `.#...` without an explicit `path:`/`git+file:` override). Nix
  auto-detects the git repository and fetches via `git+file://`.

Both run `git ls-files -z` to enumerate the tree. They read **git's index/`HEAD`**, not the
working directory, and not jj's own view of `@`. An uncommitted edit to an already-tracked file
is visible (the tree is dirty). A brand-new untracked file is NOT, until you `git add` it.

**Why this diverges from jj's own state:** `jj status`/`jj log` snapshot the working copy into
jj's commit graph (and that commit's content really is written into the shared git object
database — `git cat-file -p <jj's @ commit-id>` shows it). But jj does **not** eagerly update
git's `HEAD` or index to match `@` on every snapshot. `jj git export` (which does sync jj's
bookmarks/state to git refs) can report `Nothing changed` even while the index is stale relative
to `@`'s actual content. Confirmed in this repo on 2026-07-09: a new file showed as `A` in both
`jj status` and `git status`, was a real blob inside `@`'s git commit object, and yet
`git ls-files`/`git status --short` still reported it as `??` (untracked). `HEAD` stayed pinned at
an older commit throughout. The exact trigger for when jj does or does not push that sync is not
fully isolated — treat it as unreliable, not as a bug with a known fix.

**History:** `devenv.yaml`'s `inputs.nix-configs` was `url: path:.` until commit `d2f3e8f8`
(2026-07-31). A `path:.` input copies the raw working directory (filtered only by `.gitignore`),
so it bypassed git's index and saw a new file at once. The switch to `git+file:.` aligned devenv
with the `self` path, so both now read git's index. This means a new untracked file is now
invisible to devenv builds too, not just to `.#`-based ones.

**What works:** when a `git+file://`-backed build (a devenv build, a host switch, a `.#` CLI
invocation against `self`) must see a just-created file, do not assume `jj status`/`jj git export`
synced it. Verify with `git ls-files -- <path>` first. When it is not tracked, it needs a real
`jj describe`/`git` commit, or at least it must land in git's actual index/`HEAD`, not just in
jj's working-copy snapshot. A `path:`-based input still bypasses git's index entirely and sees new
files at once — reach for it (for example in an isolated flake test that would otherwise resolve
this repo through `/nix/store`) when you specifically need working-directory semantics.

---

## Redirect hazard: never write into the file a `jj` read is reading

**A command that reads a tracked file through `jj` must NOT redirect into that same file.** This
shape destroys the file and every copy of it in the descendants:

```bash
# WRONG — this empties devenv.lock in @ and in every descendant commit:
jj file show -r <other-rev> devenv.lock | jq '...' > devenv.lock
```

**Mechanism, in order.** The shell opens the redirect **before** it starts the pipeline, so the
working-copy file is already 0 bytes when `jj file show` runs. `jj file show` then snapshots the
working copy first, as every `jj` command does — so the empty file becomes the real content of
`@`. When `<other-rev>` is a **descendant** of `@`, jj rebases that empty file into it, and the
read returns nothing. `jq` reports a parse error and writes an empty file over the top.

Measured once in this repo: one run of the documented `devenv.lock` strip wiped `devenv.lock` in
`@` and in every descendant commit.

**Recovery:** `jj op restore <op-before-the-snapshot>`. Find the op with `jj op log`; the target
is the operation **before** the `snapshot working copy` entry that the failed command created.

**Correct shape** — read into a temporary file, transform, then `mv` into place:

```bash
jj file show -r <other-rev> devenv.lock > /tmp/in.json
jq '...' /tmp/in.json > /tmp/out.json
mv /tmp/out.json devenv.lock
```

The same rule covers `jj diff`, `jj show`, `jj file list` and any other read — the snapshot is a
property of the `jj` command, not of the subcommand. It also covers a read of a file in `@`
itself: `jj file show -r @ x | … > x` truncates `x` before the read.

---

## Worktree hazard: git worktrees share the single `.jj` store — never use one here

> ⚠️ **NEVER use a `git worktree` in this repo.** This covers any tool that creates one under the
> hood without a clear notice — e.g. Claude Code's Agent/Workflow `isolation: "worktree"` option.
> The `jj-guard` hook blocks `git worktree` outright for this reason. When you must bypass that
> block, that is the signal to stop and use `jj workspace add` instead.

**Mechanism, precisely:** a `git worktree` registers a new checkout under this repo's own
`.git/worktrees/<name>/` and gives it a `.git` file that points back there. But it does **not**
get its own `.jj` directory. It is colocated with, and shares, the *single* `.jj` store that the
main checkout uses. `jj workspace list` run from either directory shows only one workspace
(`default`), and `jj log -r @ --no-graph -T change_id` run from both directories resolves to the
identical change id. There is no real working-copy isolation, despite the separate directory.

**Why this is dangerous:** concurrent work in that worktree and the main working copy means two
processes snapshot the *same* jj change (`@`) at the same time — a straight race on jj's
working-copy state. **Confirmed in this repo on 2026-07-29:** a worktree-isolated subagent was
created nested *inside* the repo tree at `.claude/worktrees/<agent-id>/` (itself a second mistake
— a worktree must never live under the tree it checks out) while unrelated edits continued in the
main working copy. Three files just written/formatted in the main checkout (`devenv.nix`,
`modules/slots/zellij/default.nix`, `.agents/skills/zellij/SKILL.md`) were truncated to 0 bytes
mid-session — no error, no warning, just empty files. Root cause: the race above, confirmed
because both directories resolved to the same jj change id.

**Recovery, when this already happened:** do not panic-edit further. Run `jj op log --no-pager
--limit N` to find an operation from just before the corruption (e.g. right after a known-good
save/format step), then recover each affected file with:

```bash
jj file show --revision @ --at-op <op-id> <path> > /tmp/recovered-<name>
# diff/verify, then copy back into place
```

**What works:** a real second jj workspace. Read the next section before you create one — the
creation command is only step one of five, and two of the remaining steps stop a silent failure.

Before you trust *any* claimed isolation (a tool's `isolation: "worktree"` flag, a manually
created directory, anything), verify it is real:

```bash
jj workspace list                                        # must show more than one workspace
jj log -r @ --no-graph -T change_id                       # run from BOTH directories — must differ
```

When you cannot confirm a distinct change id in a genuinely distinct workspace, do not run
concurrent work there. Fall back to work in sequence in the main working copy.

---

## jj workspaces: the sanctioned parallel-isolation mechanism

Task and full evidence: [tasks/jj-workspaces-parallel-agents.md](tasks/jj-workspaces-parallel-agents.md).
Executable proof: [`checks/jj-experiments/test_workspaces.py`](../checks/jj-experiments/test_workspaces.py).
Two environment hazards that bite after setup: [vcs-workspaces.md](vcs-workspaces.md).

A workspace gives a genuinely separate working copy: its own `.jj/working_copy`, its own `@`, and
no `.git` at all. jj reconciles the shared op log by itself. Measured on jj 0.45.1: 30 concurrent
snapshots, no truncation, no loss, no divergent commit.

### Naming convention

```
~/dev/github.com/nazarewk-iac/nix-configs/            # trunk checkout
~/dev/github.com/nazarewk-iac/.nix-configs--<slug>/   # workspace
```

- Pattern: `../.<repo-dir>--<slug>/`. `<slug>` is a short kebab-case task name.
- The path must be **outside** the repo tree. A nested path risks the outer repo's file watchers
  and tools recursing into it.
- Keep the leading dot: `fd`, `rg` and most editor scans skip a hidden directory, so the sibling
  never appears in a search of the parent directory.
- **Always pass `--name <slug>`.** Without it, jj takes the workspace name from the destination
  basename and the leading dot goes into the name.

### The five steps

```bash
# 1. create it, from the trunk
jj workspace add --name <slug> -r <base-rev> ../.nix-configs--<slug>
cd ../.nix-configs--<slug>
jj new                      # start on a fresh change, never on the trunk's @

# 2. verify the isolation is real, from BOTH directories
jj workspace list           # must show more than one workspace
jj log -r @ --no-graph -T change_id      # the two values MUST differ

# 3. bootstrap the one load-bearing untracked file
cp ../nix-configs/devenv.slots.local.nix .

# 4. point the flake input at the trunk (see below); then
devenv shell

# 5. clean up when done, either order, from the trunk for `forget`
jj workspace forget <slug>
rm -rf ../.nix-configs--<slug>
```

`jj workspace update-stale` recovers a stale workspace. A repo-wide op-log rewind (`jj op restore`)
run from another workspace is the one condition known to produce one; an ordinary rewrite of the
workspace's `@` does not.

### Step 3: why the bootstrap copy is mandatory

A fresh workspace holds **tracked files only**, so every git-ignored file is absent.
`devenv.nix` loads `devenv.slots.local.nix` through
`lib.optional (builtins.pathExists ./devenv.slots.local.nix)`, so a missing file is skipped with
no warning. That silence is the whole hazard: without the copy, the workspace's slot settings
collapse to defaults, `kdn.jj.fork.enable` turns off, and the generated jj config shrinks from
2568 bytes with 4 fork aliases to a 64-byte stub with none.

Copy nothing else. `.devenv/`, `.direnv/`, `.pre-commit-config.yaml`, `.claude/settings.json`,
`.agents/skills/` and every `/nix/store` symlink regenerate on the first `devenv shell`.

### Step 4: a workspace has no `.git`, so `git+file:.` cannot resolve

`devenv.yaml` sets `inputs.nix-configs.url = git+file:.`. From a workspace that string reaches
`git ls-remote`, which reads `file:.` as an scp-style remote and tries SSH to a host named `file`:

```
ssh: Could not resolve hostname file: nodename nor servname provided, or not known
  × Lock validation failed:
         … while fetching the input 'git+file:.'
```

`flake.nix`'s `nix-configs = self` does **not** fail this way. A bare `.` degrades to a `path:`
flake, so `nix eval '.#…'` works from a workspace. That degradation carries its own cost: a
`path:` flake copies git-ignored content into the store, so every `.#` reference copies the whole
`.devenv/` tree once devenv has created it. Prefer the pinned input below over `.#` in a workspace.

**The fix: a git-ignored `devenv.local.yaml` in the workspace, with `ref` AND `rev` both set to the
same commit id.**

```yaml
inputs:
  nix-configs:
    url: git+file:///Users/<you>/dev/github.com/nazarewk-iac/nix-configs?ref=<REV>&rev=<REV>
```

```bash
jj log -r 'fork-tip' --no-graph -T commit_id     # run in the trunk to get <REV>
```

**Why `ref=` is mandatory, and `rev=` alone fails.** Nix strips every volatile attribute —
`rev`, `narHash`, `lastModified`, `revCount`, `dirtyRev`, `dirtyShortRev` — from the `locked` node
of any **local** input, and a git input counts as local when its url scheme is `file`. The code is
`src/libflake/lockfile.cc` ("Strip volatile attributes from local inputs to avoid lock file
churn"), and `isLocal` is `src/libfetchers/git.cc`. So `ref` is the **only** pin that survives into
`locked`. Set `ref` to the commit id. With no `ref`, devenv falls back to a default branch and this
repo has no `master`: `revspec 'master' not found`.

Measured against a dirty dependency tree, with devenv 2.2.3:

| url form | `locked` node | evaluated value |
|---|---|---|
| unpinned `git+file:///<abs>` | `{type, url}` — nothing volatile | the **uncommitted** working-tree value |
| `?ref=<REV>&rev=<REV>` | `{ref: <REV>, type, url}` — `rev` stripped | the **committed** value |

So the unpinned form reads the trunk's working tree on every evaluation, which re-introduces the
`prek` / `git write-tree` race. The pin ignores the working tree. Do not read a missing `rev` in
`locked` as a broken pin — `ref` is doing the work.

**`devenv -o nix-configs '<url>' <subcommand>` also works, but it must be typed every time.** A
bare `devenv` command fails even when `devenv.lock` already holds the pinned node. devenv compares
the node's `original` against `devenv.yaml` and refetches on a mismatch (`src/libflake/flake.cc`),
and devenv's `--override-input` rewrites the declared url rather than applying a sticky override.

**`devenv.local.yaml` is git-ignored; `devenv.lock` is not.** devenv rewrites the lock in the
workspace, and that cannot be avoided: `original` is written **unstripped**, so any url change lands
in it, and the staleness test is full JSON equality of the whole lock graph. Never commit that
change.

### `git-hooks` fails in a workspace — loudly, but it does not block the shell

Because a workspace has no `.git`, the `git-hooks` integration cannot install. Measured on
2026-09-09, this is not a silent skip: the devenv task **fails** and the failure cascades.

```
WARNING: git-hooks.nix: skipping hook installation: fatal: not a git repository
error: Command `git rev-parse --show-toplevel` exited with an error: exit status: 128
✖ Running devenv:git-hooks:run in 881ms (failed)
✖ Running devenv:enterTest in 334ns (dependency failed)
✖ Running tasks in 5.16s (failed)
```

The shell still enters, and `devenv shell -- <cmd>` still exits 0. `.pre-commit-config.yaml` is
still symlinked and `prek` is still on `PATH` — they simply have no repo to act on. So expect this
output in every workspace shell and do not read it as a broken bootstrap. It also means a workspace
runs **no** pre-commit checks; run the formatter and the linters from the trunk before you commit.

### devenv state is per directory

`DEVENV_ROOT`, `DEVENV_DOTFILE`, `DEVENV_STATE` and the `devenv.runtime` socket directory all
derive from the shell's directory, so the trunk and a workspace never collide. Measured:
`/tmp/devenv-18f6d5f` (trunk) against `/tmp/devenv-34e4006` (workspace).

One `DEVENV_*` hazard remains, and it is the inherited-environment case in
[vcs-workspaces.md](vcs-workspaces.md): `DEVENV_ROOT` is fixed at shell-entry time and does not
follow a later `cd`. Enter `devenv shell` **from the workspace root**.

### The shared jj repo config is the one devenv target that is not per workspace

`jj config path --repo` returns **one shared file** for the trunk and every workspace. The id in
that path comes from `.jj/repo/config-id`, a random value written once at `jj git init`, and a
secondary workspace reaches the same store through its `.jj/repo` pointer file.

`modules/slots/jj/default.nix` therefore guards its `enterShell` symlink. The guard asks whether
`.jj/repo` is a **file**, which is true only in a secondary workspace — it is a directory in the
default workspace. That polarity is deliberate: an unknown future jj layout then makes the shell
write the file, which is today's behaviour, instead of making the default workspace lose its
config. A workspace prints `kdn.jj: secondary jj workspace — the shared jj repo config stays
untouched` and inherits the trunk's aliases instead. `jj config path --workspace` is per workspace
and is unaffected.

Verified live on 2026-09-09 from a real workspace: the message appeared, and the shared config
stayed byte-identical (`sha256 7656a6c2…` before and after) with all 4 fork-alias mentions intact.

### A workspace never activates a system

**A workspace evaluates, builds and tests. It never activates.** Activation is machine-global, not
directory-scoped: a `switch` replaces `/run/current-system`, restarts services and mutates `/etc`.
Two workspaces cannot each hold a different current system, and the trunk cannot detect that a
workspace overwrote its activation. A parallel agent has no mandate to change the machine.

Allowed: `nix build`, `nix eval`, `nix flake check`, `nix run '.#darwin-rebuild' -- build`,
`./nixos-rebuild.sh build`, `devenv shell`/`eval`/`build shell`, pytest, formatters, linters.

Forbidden: any `switch`/`boot`/`test` activation, `home-manager switch`, anything that needs sudo
to change the running system, and `git push` / `jj git push` / `jj sync-remotes` /
`jj bookmark set`. A `switch` and a push are always the user's call, from the trunk.

---

## Required finish state

After you **finish** a work session, `@` must be empty (no description, no content) on top of the
correct parent. This is the wrap-up step from "When to leave an empty change on top" above. Do it
only when the described work below `@` is complete — not to park half-done work.

```bash
# leave @ empty on top of the current tip:
jj new
```

**Before you declare done:**
```bash
# check for stray commits (orphans from rebases, or undescribed changes left in the middle):
jj log -r '::(@ | bookmarks())' --no-graph -T 'change_id.short() ++ " " ++ bookmarks ++ " " ++ description.first_line() ++ "\n"'

# verify the build:
devenv build shell
```

Ask the user whether to squash, relocate, or abandon any stray you find. An undescribed change
that is NOT the tip working copy is a stray — describe it, fold it, or abandon it. Fix build
errors before you finish. When this repo has a fork remote configured, see
[jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for the fork-specific finish state (dual-parent `@`,
`upstream-tip`/`fork-tip` bookmark advancement).

---

## Day-to-day golden paths

The shortest correct command for each common jj operation. Every path below is verified by a test
in `checks/jj-experiments/` (branch-agnostic; run `pytest checks/jj-experiments/`). The paired
`test_<group>.md` holds the detail and the caveats. Fork and branch-topology cases (change
placement, pull upstream in, frozen-vs-mutable, forbidden rewrites) live in
[jujutsu-vcs.fork.md](jujutsu-vcs.fork.md).

### Golden-path index

| Operation | Golden path | Detail |
|---|---|---|
| Read a file at a revision | `jj file show -r <rev> <path>` | [test_inspect.md](../checks/jj-experiments/test_inspect.md) |
| Diff a commit / a range | `jj diff -r <id>` · `jj diff --from <X> --to <Y>` (`--stat`, `--name-only`) | [test_inspect.md](../checks/jj-experiments/test_inspect.md) |
| Read the graph | `jj log --no-pager -r '<revset>' -T '<template>'` | [test_inspect.md](../checks/jj-experiments/test_inspect.md) |
| Amend in place | `jj edit <id>` … edit … `jj new <tip>` | [test_amend.md](../checks/jj-experiments/test_amend.md) |
| Fold a fixup down | `jj squash --into <id>` | [test_amend.md](../checks/jj-experiments/test_amend.md) |
| Reword | `jj describe -r <id> -m '…'` | [test_amend.md](../checks/jj-experiments/test_amend.md) |
| Auto-route fixups | `jj absorb` | [test_squash_absorb.md](../checks/jj-experiments/test_squash_absorb.md) |
| Squash chosen files | `jj squash --from @ --into <id> -- <files>` | [test_squash_absorb.md](../checks/jj-experiments/test_squash_absorb.md) |
| Reorder two changes | `jj rebase -r <A> --insert-after <B>` | [test_restructure.md](../checks/jj-experiments/test_restructure.md) |
| Split a committed commit | `jj split -r <id> -m '…' -- <files>` | [test_restructure.md](../checks/jj-experiments/test_restructure.md) |
| Abandon a change | `jj abandon <id>` | [test_restructure.md](../checks/jj-experiments/test_restructure.md) |
| Revert-forward (pushed) | `jj revert -r <id> --insert-after <tip>` | [test_restructure.md](../checks/jj-experiments/test_restructure.md) |
| Duplicate (cherry-pick) | `jj duplicate <id> --onto <dest>` | [test_restructure.md](../checks/jj-experiments/test_restructure.md) |
| Drop a redundant merge parent | `jj simplify-parents -r <merge>` | [test_restructure.md](../checks/jj-experiments/test_restructure.md) |
| Discard one file / all of `@` | `jj restore <path>` · `jj restore` | [test_recover.md](../checks/jj-experiments/test_recover.md) |
| Restore a file from a revision | `jj restore --from <rev> <path>` | [test_recover.md](../checks/jj-experiments/test_recover.md) |
| Roll back | `jj undo` (last op) · `jj op log` + `jj op restore <op>` (multi-step) | [test_recover.md](../checks/jj-experiments/test_recover.md) |
| Bookmark CRUD | `jj bookmark create/set[/--allow-backwards]/delete/list --all-remotes` | [test_bookmarks.md](../checks/jj-experiments/test_bookmarks.md) |
| Push / fetch a bookmark | `jj git push --remote <r> --bookmark <b>` · `jj git fetch --remote <r>` | [test_bookmarks.md](../checks/jj-experiments/test_bookmarks.md) |
| Push a change to a branch/fork | fetch · `jj rebase -b @ -d <branch>@<remote>` · set · `jj git push -b <branch>` | [test_push.md](../checks/jj-experiments/test_push.md) |
| Inspect what you fetched | `jj op show @` · `jj log -r '@..main@<remote>'` (all incoming) · `jj log -r 'main@<remote>..@ & ~empty()'` (divergence) | [test_rebase.md](../checks/jj-experiments/test_rebase.md) |
| Merge in incoming changes | `jj new <mine> <incoming-tip> -m 'chore(upstream): merge'` | [test_rebase.md](../checks/jj-experiments/test_rebase.md) |
| Untrack a file | add to `.gitignore`, then `jj file untrack <path>` | [test_bookmarks.md](../checks/jj-experiments/test_bookmarks.md) |
| Detect / resolve a conflict | `jj log -r 'conflicts()'` → edit to merged content → snapshot | [test_conflicts.md](../checks/jj-experiments/test_conflicts.md) |

### Notes and gotchas

- `jj status` takes no `-r`. To read another revision use `jj diff -r <rev>` or `jj show <rev>`.
  Always pass `--no-pager` in a non-interactive shell.
- `jj edit`, `jj describe`, `jj squash`, `jj absorb`, and `jj rebase` all **rewrite** commits, so
  they work only on **mutable** commits. jj refuses to rewrite a pushed or immutable commit —
  build forward instead. To undo a pushed change, revert-forward with `jj revert`.
- `jj absorb` sends each hunk to the mutable ancestor that last touched those lines. It skips
  immutable ancestors and leaves ambiguous hunks in `@`. Use explicit `jj squash --from/--into --
  <files>` when you need a specific target.
- `jj file untrack` needs the path gitignored first, or the next snapshot re-adds it. The
  subcommand is `jj file untrack`, not `jj untrack`.
- `jj bookmark set` refuses a backward or sideways move without `--allow-backwards`.
- jj records a conflict **inside** the commit with its own markers (`<<<<<<<` / `%%%%%%%` /
  `>>>>>>>`). Detect with `jj log -r 'conflicts()'`; resolve by editing each file to the merged
  content and running any jj command to snapshot. Never run the interactive `jj resolve` in an
  agent — it opens a merge tool and hangs.
- After `jj edit <interior commit>`, a plain `jj new` makes a child of that commit; run `jj new
  <tip>` to return to the tip.

### Branch and fork topology

[Branch workflows](#branch-workflows) below cover the shared long-lived-branch operations
(integrate trunk, the frozen-vs-mutable rule, hazards, X→Y). A fork is one instance of that model.
The fork-specific extras — content routing, `jj fork-audit`, and the two-remote sync — are in
[jujutsu-vcs.fork.md](jujutsu-vcs.fork.md), verified by `test_placement.py`, `test_rebase.py`,
`test_hazards.py`, `test_deleak.py`, `test_advanced.py`, and `test_revsets.py`.

---

## Branch workflows

A long-lived branch tracks a shared trunk and integrates new trunk from time to time, staying a
mutable line on top of it. A fork is one instance of this model — a merge-style branch plus a
content-routing and a second-remote layer (see
[jujutsu-vcs.fork.md](jujutsu-vcs.fork.md)). The recipes here are trunk-agnostic and verified by
[test_branch.md](../checks/jj-experiments/test_branch.md); the hazards by
[test_hazards.md](../checks/jj-experiments/test_hazards.md).

Handy aliases for a branch off a trunk (the fork slot ships the fork analogs — see the fork doc):
`trunk-incoming` = `@..main@<remote>` (fetched but unmerged trunk), `trunk-incoming-tip` =
`main@<remote>`, `branch` = `trunk()..@ & ~description("")`, `branch-tip` = `heads(branch)`.

### Add a change to the branch

A plain split on top — no merge needed:

```bash
jj split -m 'feat: ...' -- <files>
```

When the branch keeps a merge with trunk (the fork's shape), place the change with `-A`/`-B`
instead — see the fork doc's placement recipe.

### Inspect what you fetched

Before you integrate, read the topology of what a fetch brought in. Verified by
`test_inspect_incoming_after_fetch` in [test_rebase.md](../checks/jj-experiments/test_rebase.md)
(branch-agnostic):

```bash
jj git fetch --all-remotes
jj op show @                              # what THIS fetch changed: arrived commits + moved bookmarks
jj op diff --from @- --to @               # the same, as a diff between two operations
jj log -r '@..main@<remote>'              # ALL incoming commits (the full new range)
jj log -r 'main@<remote>..@ & ~empty()'   # your divergence; empty ⇒ strictly behind (fast-forward)
jj log -r 'heads(::@ & ::main@<remote>)'  # the merge base (last shared commit)
```

Use `@..<incoming>` for the whole incoming range — `<incoming> ~ ::@` reports only the tip (a
bookmark resolves to one commit). `jj op show @` right after a fetch is the clearest report of what
you just pulled in: it lists each arrived commit and every bookmark that moved.

### Integrate new trunk

Fetch, then either rebase the branch onto the new trunk (linear) or merge the new trunk in (keeps a
merge):

```bash
jj git fetch --all-remotes
# rebase — linear, needs a mutable branch:
jj rebase -s 'roots(branch)' -d 'trunk-incoming-tip'
# or merge — keeps a merge (the fork's shape):
jj new branch-tip trunk-incoming-tip -m 'merge trunk'
```

Either way `trunk-incoming` ends empty and the pushed trunk keeps its commit id. **Frozen-vs-mutable
rule:** you can rebase or rewrite only a **mutable** branch. A pushed commit is immutable, so build
forward — add a new merge — instead of a rewrite. A conflict is recorded in the commit, not aborted:
detect it with `jj log -r 'conflicts()'`, edit each file to the merged content, then snapshot.

### Push the branch to a remote

Publish your work to a shared branch, a feature branch, or a fork remote. Fetch first, put your
work on top of the incoming tip, then push:

```bash
jj git fetch --remote=<remote>
jj rebase -b @ -d <branch>@<remote>       # skip if you are already ahead
jj bookmark set <branch> -r <your-rev>
jj git push --remote=<remote> -b <branch>
```

- **Safe default — push a feature/PR branch, never over the primary.** Do not `jj bookmark set main`
  and push; publish your own branch and open a PR. Anonymous (usual): `jj git push -c <rev>` creates a
  `push-<id>` bookmark and pushes it. Named: `jj bookmark create <name>` then `jj git push -b <name>`
  — jj 0.44 has no `--allow-new`; the push starts tracking the new bookmark. Both leave `main@<remote>`
  untouched. The fork remote is the same command with `--remote=<fork>`.
- **Move your work, not the incoming.** You cannot rebase the fetched tip under your work when it is
  immutable: `main@<remote>` (`trunk()`, always) or an untracked bookmark — `jj rebase -r … --insert-before @`
  is refused. Rebase your own mutable stack (`-b @`) or one change (`-r <tip>`) onto it instead. (The
  insert *does* work on a **tracked, non-trunk feature branch**: `jj bookmark track feat@<remote>` first.)
- **A stale push is rejected; a post-fetch push can clobber.** With force-with-lease, a push made
  **before** you fetch the moved remote is **rejected** ("stale info") — the real guard. Only **after**
  a fetch does a bare push move the bookmark **sideways** and discard the remote's commit. So fetch,
  then rebase onto the incoming tip so the push fast-forwards; `jj git push … --dry-run` shows "move
  sideways" when it would clobber. There is no fast-forward-only flag.

Verified by [test_push.md](../checks/jj-experiments/test_push.md).

### Make X an ancestor of Y

`Y` needs a change `X` in its ancestry, and `Y` keeps its existing parent:

```bash
jj rebase -s Y -d X -d <Y-existing-parent>   # Y becomes merge(X, old parent)
```

### Hazards

- **Never rewrite a pushed or immutable commit.** `jj describe`/`jj squash --into`/`jj rebase` on
  it fail with `Commit <id> is immutable`. Build forward instead.
- **Never `jj describe` a dual-parent `@`** (a merge-style branch). It becomes a described merge
  that keeps both parents. Commit on a single-parent `@`, then restore the dual-parent `@`.
- **`branch-tip` and the `*-tip` aliases follow commit time** (`latest()`), not graph position. Fix
  the commit time if a tip resolves to the wrong commit.

---

## Without a fork (upstream-only)

`upstream` bookmark tracks the public remote's tip. `@` sits directly on top of it:

```
<upstream-remote>/main ──► ... ──► upstream ──► @
```

`upstream` is a **bookmark** name in this repo's convention, distinct from the **remote** name
(e.g. `kdn`, configurable via `kdn.jj.upstream.remote`). Do not confuse the two when you read a
revset like `main@<upstream-remote>`.

After you fetch, keep `@` current:

```bash
jj git fetch --remote=<upstream-remote>
jj rebase -s @ -d main@<upstream-remote>    # onto the freshly fetched tip
```

---

## Split changes

`jj split` is the primary tool to carve accumulated work into separate commits. It opens an
editor by default — useful in a terminal, but it hangs in an agent context. Pass `-m` and `--`
to skip the editor:

```bash
jj split                                                  # interactive: pick hunks/files
jj split -m 'fix(...): desc' -- path/to/file              # non-interactive: by file
jj split -m 'fix(...): desc' -- path/to/a.txt path/to/b.txt  # multiple files at once
```

After a split, the selected changes become a new named commit as `@`'s parent. The remaining
(non-selected) changes stay in `@`.

---

## Bookmark hygiene

Point a bookmark at the commit you just carved out of `@` (the change ID `jj split` left behind),
not at the current `@`:

```bash
jj split -m 'chore(flake): update' -- flake.lock
# or by explicit change ID (unambiguous, good in scripts):
jj bookmark set upstream -r <change-id>
# or by revset — picks the latest named commit:
jj bookmark set upstream -r 'upstream-tip'
```

See [jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for bookmark hygiene in a fork context
(`upstream-tip`, `fork-tip`).
