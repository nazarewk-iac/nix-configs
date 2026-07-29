---
type: Reference
description: Practical jj (Jujutsu) version control patterns and conventions used in this repo.
timestamp: 2026-07-10T12:19:48+02:00
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
branch/tag mutation — has a direct jj equivalent and must go through jj instead, so jj's model
(mutable commits, change IDs, op log) stays authoritative. See the `jujutsu-vcs` rule for the
full mandate and the reasoning behind each exception.

---

## The working copy (@)

`@` is your scratch space: an unnamed change where edits accumulate. Unlike git's staging area,
there's nothing to "add" — `@` auto-snapshots on every `jj` command. Keeping `@` empty (unnamed,
no content) once you're done working is a **manually maintained convention in this repo**, not
something jj enforces or automates. `jj describe` labels `@` with a message; `@` is now that
named, non-empty commit — jj does not create a new empty change on top for you. Only certain
commands that split content off `@` (see below) leave a fresh commit behind, because that's
inherent to how they partition changes, not a general auto-refresh behavior.

```bash
# accumulate edits in @, then carve out what's done:
jj split -m 'feat(...): description' -- path/to/file
# the *remaining* (non-selected) changes stay in @; the selected changes become a new
# commit as @'s parent
```

### Preferred flow: split and squash, not rebase

**Never create a new commit before making changes.** Let edits accumulate in `@`, then:

- Use `jj split -- <files>` to carve part of `@` into a new named commit (accepts multiple
  `-- path1 path2 ...`).
- Use `jj squash --from @ --into <target>` to fold `@` into an existing unpushed commit.

**Rebase is a last resort** — it moves commits around and can scramble parent relationships,
especially in a fork workflow with multiple merge commits. Prefer:

```bash
# wrong: create a commit up front, then wrestle with rebases to fix topology
jj new upstream -m 'feat: thing'
# ...make changes...

# right: make changes in @, then split/squash into the right place
# ...make changes in @...
jj split -m 'feat: thing' -- path/to/file          # carve off into a new named commit
jj squash --from @ --into <change-id> -m 'msg'     # fold into an existing commit
```

`jj rebase` remains legitimate when the graph topology genuinely needs changing (e.g. after
fetching new upstream commits that a merge must absorb — see
[jujutsu-vcs.fork.md](jujutsu-vcs.fork.md)), or when constructing/restoring a merge commit
(`jj new <a> <b>`) — these are structural operations, not work checkpoints.

---

## Colocation hazard: `nix build/eval '.#...'` can see stale content

**New or modified files may be invisible to `nix build`/`nix eval '.#...'` and to real host
switches, even though `jj status` and `git status` both show them.** This is a real, confirmed
footgun — verify with `git ls-files -- <path>` before trusting a build that touches a just-edited
file, if that build goes through the flake's own `self` (host configs, `darwinConfigurations`,
`nixosConfigurations` — anything reached via the CLI's `.#` shorthand).

**Mechanism, precisely:** this repo has two different ways Nix pulls in this repo's own source
tree, and they behave differently:

- `devenv.yaml`'s `nix-configs: url: path:.` (used by `modules/slots/*/default.nix`'s
  `inputs.nix-configs` self-references, and by devenv builds generally) uses Nix's plain `path:`
  fetcher. It copies the raw working directory, filtered only by `.gitignore` — new files are
  visible immediately, no VCS action required.
- `flake.nix`'s `nix-configs = self` (used by `kdnMetaModule`, and by `self` itself whenever the
  CLI resolves a local flake via `.#...` without an explicit `path:`/`git+file:` override) gets
  auto-detected by Nix as a git repository and fetched via `git+file://`. This fetcher runs
  `git ls-files -z` to enumerate the tree — it reads **git's index/`HEAD`**, not the working
  directory, and not jj's own view of `@`.

**Why this diverges from jj's own state:** `jj status`/`jj log` snapshot the working copy into
jj's commit graph (and that commit's content really is written into the shared git object
database — `git cat-file -p <jj's @ commit-id>` will show it). But jj does **not** eagerly update
git's `HEAD` or index to match `@` on every snapshot; `jj git export` (which does sync jj's
bookmarks/state to git refs) can report `Nothing changed` even while the index is stale relative
to `@`'s actual content — confirmed empirically in this repo on 2026-07-09: a new file showed as
`A` in both `jj status` and `git status`, was a real blob inside `@`'s git commit object, and yet
`git ls-files`/`git status --short` kept reporting it as `??` (untracked) and `HEAD` stayed pinned
at an older commit throughout. The exact trigger for when jj does vs. doesn't push that sync
wasn't fully isolated — treat it as unreliable rather than as a bug with a known fix.

**What doesn't fix it:** swapping `devenv.yaml`'s `inputs.nix-configs` from `url: path:.` to a
`git+file://.`-style URL, hoping to force a fresh read, does **not** fix this for devenv builds —
confirmed not viable as of 2026-07-09.

**What actually works:** use a `path:`-based input (as `devenv.yaml` already does for
`inputs.nix-configs`) wherever possible, since it bypasses git's index entirely. When a
`git+file://`-backed build (host switches, `.#` CLI invocations against `self`) must see a
just-created or just-edited file, don't assume `jj status`/`jj git export` synced it — verify with
`git ls-files -- <path>` first, and if it's not tracked, it needs a real `jj describe`/`git`
commit or at minimum to land in git's actual index/`HEAD`, not just in jj's working-copy snapshot.

---

## Worktree hazard: git worktrees share the single `.jj` store — never use one here

> ⚠️ **NEVER use a `git worktree` in this repo.** This includes tooling that creates one under the
> hood without saying so — e.g. Claude Code's Agent/Workflow `isolation: "worktree"` option.
> `git worktree` is blocked outright by the `jj-guard` hook for this reason; if you find yourself
> needing to bypass that block, that's the signal to stop and use `jj workspace add` instead.

**Mechanism, precisely:** a `git worktree` registers a new checkout under this repo's own
`.git/worktrees/<name>/` and gives it a `.git` file pointing back there — but it does **not** get
its own `.jj` directory. It is colocated with, and shares, the *single* `.jj` store that the main
checkout uses. `jj workspace list` run from either directory shows only one workspace
(`default`), and `jj log -r @ --no-graph -T change_id` run from both directories resolves to the
identical change id — there is no actual working-copy isolation, despite the separate directory.

**Why this is dangerous:** running work in that worktree concurrently with the main working copy
means two processes are snapshotting the *same* jj change (`@`) at the same time — a straight
race on jj's working-copy state. **Confirmed empirically in this repo on 2026-07-29:** a
worktree-isolated subagent was created nested *inside* the repo tree at
`.claude/worktrees/<agent-id>/` (itself a second mistake — worktrees should never live under the
tree they check out) while unrelated edits continued in the main working copy. Three files that
had just been written/formatted in the main checkout (`devenv.nix`,
`modules/slots/zellij/default.nix`, `.agents/skills/zellij/SKILL.md`) were silently truncated to
0 bytes mid-session — no error, no warning, just empty files. Root-caused to the race above by
confirming both directories resolved to the same jj change id.

**Recovery, if this has already happened:** don't panic-edit further. `jj op log --no-pager
--limit N` to find an operation from just before the corruption (e.g. right after a known-good
save/format step), then recover each affected file with:

```bash
jj file show --revision @ --at-op <op-id> <path> > /tmp/recovered-<name>
# diff/verify, then copy back into place
```

**What actually works:** if parallel, filesystem-isolated work is genuinely needed, create a real
second jj workspace instead — and put it *outside* this repo's directory tree, never nested
under it:

```bash
jj workspace add ../nix-configs-ws-<name>   # sibling directory, NOT ./something-under-here
cd ../nix-configs-ws-<name> && jj new       # start the isolated work on a fresh change, not @
```

Before trusting *any* claimed isolation (a tool's `isolation: "worktree"` flag, a manually created
directory, anything), verify it's real:

```bash
jj workspace list                                        # must show more than one workspace
jj log -r @ --no-graph -T change_id                       # run from BOTH directories — must differ
```

If you can't confirm a distinct change id in a genuinely distinct workspace, don't run concurrent
work there — fall back to doing the work sequentially in the main working copy.

---

## Required finish state

After any work session, `@` must be empty (no description, no content) with the correct parent:

```bash
# leave @ empty on top of the current tip:
jj new
```

**Before declaring done:**
```bash
# check for stray commits (orphans from rebases):
jj log -r '::(@ | bookmarks())' --no-graph -T 'change_id.short() ++ " " ++ bookmarks ++ " " ++ description.first_line() ++ "\n"'

# verify the build:
devenv build shell
```

Ask the user whether to squash, relocate, or abandon any strays found. Fix build errors before
finishing. If this repo has a fork remote configured, see
[jujutsu-vcs.fork.md](jujutsu-vcs.fork.md) for the fork-specific finish state (dual-parent `@`,
`upstream-tip`/`fork-tip` bookmark advancement).

---

## Without a fork (upstream-only)

`upstream` bookmark tracks the public remote's tip. `@` sits directly on top of it:

```
<upstream-remote>/main ──► ... ──► upstream ──► @
```

`upstream` is a **bookmark** name in this repo's convention, distinct from the **remote** name
(e.g. `kdn`, configurable via `kdn.jj.upstream.remote`) — don't confuse the two when reading
revsets like `main@<upstream-remote>`.

After fetching, keep `@` current:

```bash
jj git fetch --remote=<upstream-remote>
jj rebase -s @ -d upstream    # or: -d main@<upstream-remote>
```

---

## Splitting changes

`jj split` is the primary tool for carving accumulated work into separate commits. It opens an
editor interactively by default — useful in a terminal, but hangs in agent contexts. Pass `-m`
and `--` to skip the editor:

```bash
jj split                                                  # interactive: pick hunks/files
jj split -m 'fix(...): desc' -- path/to/file              # non-interactive: by file
jj split -m 'fix(...): desc' -- path/to/a.txt path/to/b.txt  # multiple files at once
```

After splitting, the selected changes become a new named commit as `@`'s parent; the remaining
(non-selected) changes stay in `@`.

---

## Bookmark hygiene

Point bookmarks at the commit you just carved out of `@` (the change ID `jj split` left behind),
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
