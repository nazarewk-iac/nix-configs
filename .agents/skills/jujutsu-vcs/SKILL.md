---
name: jujutsu-vcs
description: jj version control patterns — working copy, split/squash, bookmarks, fork rebase. Single source of truth for jj usage in this repo; use whenever reaching for a raw git command, or when working with jj commits, splits, rebases, or bookmark management.
type: Skill
timestamp: 2026-07-10T12:19:48+02:00
---

<!--
  Agent-safety notes below are informed by two external MIT-licensed sources:
  danverbraganza/jujutsu-skill, and stevenhobartwork-create/claude-plugin-jj-english
  (English translation of kawaz/claude-plugin-jj). Content here is filtered/rewritten for this
  repo's @-only convention (neither source's "jj new per task" workflow is used here).
-->

Full reference: [docs/jujutsu-vcs.md](../../../docs/jujutsu-vcs.md), fork topology:
[docs/jujutsu-vcs.fork.md](../../../docs/jujutsu-vcs.fork.md). For deep troubleshooting, use the
`jj-expert` subagent.

## Key rules for agents

- **`@` staying empty is a manual convention, not automatic** — `jj describe`/`jj commit` do NOT
  create a fresh empty `@` afterward. Run `jj new` yourself when you actually want a new empty
  change (rare — usually only for fork merge-commit topology).
- **Never pre-create commits** — accumulate changes in `@`, then `jj split` or `jj squash --into`.
- **`jj split` / `jj describe` / `jj squash` open an editor** — always pass `-m 'msg'` and
  `-- <files>` in non-interactive contexts. `jj split` accepts multiple files:
  `jj split -m msg -- a.txt b.txt`.
- **Never interactive** — `jj split -i`, `jj commit -i`, `jj squash -i`, `jj resolve` all open an
  interactive picker/merge tool and will hang in an agent context. Use fileset arguments instead.
- **Never `jj edit` to read a file** — use `jj file show --revision <id> <path>` instead.
- **Start investigations with `jj config list` variants, not by reading `.jj/` files** — `jj
  config list --repo` (most common) shows this repo's revset aliases, bookmark helpers, and other
  repo-scoped settings; plain `jj config list` (or `--include-defaults`) covers user/default
  scope. Never poke at files under `.jj/` directly — they're an internal store, not a config
  surface. **If `--repo` output is empty or just a lone `"#schema"` line, something is probably
  wrong** — this repo ships repo-scoped config via devenv. The agent **cannot re-enter the devenv
  shell itself**, so **pause, ask the user to re-enter the devenv shell (and resume the session)**
  before relying on any repo-specific revset alias or helper.
- **Bookmarks go on the commit you just carved out** (the change ID `jj split` left behind) — not
  on the current `@`. (In a fork repo, that anchor is usually `upstream-tip` — see Fork topology.)
- **Rebase is a last resort** — only when graph topology genuinely needs fixing, or to construct
  a merge commit (`jj new <a> <b>`).
- **`--no-pager`** on `jj log`/`jj diff`/`jj show` avoids pager hangs in non-interactive shells.
- **Claude Code's `/commit` slash command runs raw `git commit`** — it bypasses jj entirely and
  the `jj-guard` hook can't intercept it (not a Bash tool call). Never use it here; use
  `jj describe`/`jj commit` instead.
- **Stale `.git/index.lock`**: if a git-backed check fails claiming the index is locked, check
  `ls -la .git/index.lock` — if no git process is actually running, it's a stale colocation
  artifact safe to remove. In agent contexts, chain related jj operations into a single Bash call
  to avoid races with background hooks.
- ⚠️ **NEVER use a git worktree here** (this includes the Agent/Workflow tool's
  `isolation: "worktree"` option — it creates a plain `git worktree`, colocated, with no `.jj` of
  its own, sharing this repo's single `.jj` store). Running it concurrently with the main working
  copy races two writers on the same jj change and **will corrupt files** — confirmed 2026-07-29,
  files silently truncated to 0 bytes. If parallel isolated work is truly needed, use
  `jj workspace add <path>` with `<path>` a sibling directory OUTSIDE this repo's tree (never
  nested under it), then `jj new` inside it immediately. Verify with `jj workspace list` (>1
  entry) and by confirming `jj log -r @ --no-graph -T change_id` differs between directories
  before trusting any isolation claim.

## Working copy state

```bash
jj st                                           # what's changed
jj log --no-pager --limit 8                     # recent graph
jj file show --revision <id> path/to/file       # read a file from any revision
jj op log --no-pager                            # operation history
jj undo                                         # undo last operation (safe escape hatch)
```

## Commit flow

```bash
# accumulate changes in @, then carve/fold instead of describing @ directly:
jj split -m 'fix(...): desc' -- path/to/file    # carves selected files into a new commit;
                                                 # remaining changes stay in @
jj squash --from @ --into <id> -m 'msg'         # fold @ into an existing commit
```

For placing a split at a precise point (`-A`/`-B`), see **Fork topology** below — in this repo
that's the common case, but the `-A <after> -B <before>` mechanism itself is general.

## Quick reference

| Command | Purpose |
|---|---|
| `jj abandon <id>` | Remove a commit; descendants rebase onto its parent |
| `jj undo` | Reverse the last operation |
| `jj absorb` | Auto-distribute working-copy changes into the ancestor commits that touched the same lines |
| `jj duplicate <id>` | Copy a commit elsewhere (git's cherry-pick equivalent) |

## Fork topology

> **Fork-only — skip this entire section if the repo has no fork.** Everything below assumes the
> `main`/`upstream` dual-parent fork setup and the repo-scoped `upstream-tip`/`fork-tip` revset
> aliases that come with it. A plain (non-fork) repo has none of these — there `@` is linear,
> you advance a single bookmark, and the ordinary `jj split -m … -- <files>` / `jj squash --into`
> flow above is all you need. Don't reach for `upstream-tip`/`fork-tip` or `-A/-B` placement
> unless this repo actually is a fork (quick check: `jj config list --repo` lists
> `revset-aliases.fork-tip`).

See [jujutsu-vcs.fork.md](../../../docs/jujutsu-vcs.fork.md) for the `main`/`upstream` dual-parent
`@` topology, bookmark hygiene with `upstream-tip`/`fork-tip`, and
rebasing the fork merge after new upstream commits.

**Advancing the upstream bookmark** after carving a new upstream commit:

```bash
jj bookmark set upstream -r 'upstream-tip'      # advance bookmark to the latest named upstream commit
```

**Placing a split precisely with `-A`/`-B` (prefer this over manual rebase surgery).** When
`@` is the dual-parent fork merge (or otherwise sits above where the commit belongs), carve the
files out *and* position the new commit in one step by giving `jj split` an explicit insertion
point — `-A <after>` / `-B <before>`. Use the `upstream-tip`/`fork-tip` aliases as the anchors so
it keeps working as the chain grows:

```bash
# land a new upstream commit between the current upstream tip and the fork merge, in one command:
jj split -A upstream-tip -B fork-tip -m 'docs: add X' -- docs/x.md
```

Because `upstream-tip` = `latest(upstream-chain)` (dynamic), splitting several commits this way
one after another naturally **stacks them in order** between the previous tip and `fork-tip` —
no follow-up rebase needed. This is far less error-prone than describing `@`, then rebasing the
result into place by hand. **Always prefer the `upstream-tip`/`fork-tip` aliases** as anchors
over raw change IDs.

> **Prerequisite — `fork-tip` should be the dual-parent merge for this to work cleanly.** The
> `-B fork-tip` trick assumes `fork-tip` is the fork merge commit sitting above `upstream-tip`,
> so a new upstream commit slots in *below* the merge (and the merge rebases to include it). If
> `fork-tip` **isn't a merge yet** (e.g. it's a plain fork commit, or the fork chain hasn't been
> merged onto the new upstream tip), it very likely **should become one first** — construct it
> with `jj new -m 'chore(upstream): merge' upstream-tip fork-tip` (the standard merge message;
> creating the dual-parent `@` = fork merge), then the `jj split -A upstream-tip -B fork-tip …`
> pattern applies.

> **If `upstream-tip`/`fork-tip` don't resolve** in a repo you know is a fork, the repo-scoped
> aliases aren't loaded — this is the "empty `jj config list --repo`" case from **Key rules
> above**: pause and ask the user to re-enter the devenv shell (the agent can't do it itself),
> don't fall back to raw change IDs. (In a non-fork repo these aliases are *expected* to be
> absent — not an error, this section just doesn't apply.)

## Deep troubleshooting

For divergent changes, conflict markers (`??` bookmarks, 3-way conflicts), revset/fileset/template
syntax questions, or graph surgery beyond split/squash — the `jj-expert` subagent activates
automatically and has a full decision tree and git↔jj mapping reference.
