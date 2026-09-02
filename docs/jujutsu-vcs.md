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

**What works:** when parallel, filesystem-isolated work is genuinely needed, create a real second
jj workspace instead. Put it *outside* this repo's directory tree, never nested under it:

```bash
jj workspace add ../nix-configs-ws-<name>   # sibling directory, NOT ./something-under-here
cd ../nix-configs-ws-<name> && jj new       # start the isolated work on a fresh change, not @
```

Before you trust *any* claimed isolation (a tool's `isolation: "worktree"` flag, a manually
created directory, anything), verify it is real:

```bash
jj workspace list                                        # must show more than one workspace
jj log -r @ --no-graph -T change_id                       # run from BOTH directories — must differ
```

When you cannot confirm a distinct change id in a genuinely distinct workspace, do not run
concurrent work there. Fall back to work in sequence in the main working copy.

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

### Fork / branch topology

For change placement (generic vs fork-sensitive content), pulling new upstream in, the
frozen-vs-mutable rules, and the forbidden rewrites, see
[jujutsu-vcs.fork.md](jujutsu-vcs.fork.md). Those cases are verified by `test_placement.py`,
`test_rebase.py`, `test_hazards.py`, `test_deleak.py`, `test_advanced.py`, and `test_revsets.py`.

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
jj rebase -s @ -d upstream    # or: -d main@<upstream-remote>
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
