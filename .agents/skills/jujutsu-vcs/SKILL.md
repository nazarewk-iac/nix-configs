---
name: jujutsu-vcs
description: jj version control patterns — working copy, split/squash, bookmarks, fork rebase. Single source of truth for jj usage in this repo; use whenever reaching for a raw git command, or when working with jj commits, splits, rebases, or bookmark management.
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
- **Bookmarks go on the commit you just carved out** (the change ID `jj split` left behind, or
  `upstream-tip`) — not on the current `@`.
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
jj bookmark set upstream -r 'upstream-tip'      # advance bookmark to the latest named commit
```

## Quick reference

| Command | Purpose |
|---|---|
| `jj abandon <id>` | Remove a commit; descendants rebase onto its parent |
| `jj undo` | Reverse the last operation |
| `jj absorb` | Auto-distribute working-copy changes into the ancestor commits that touched the same lines |
| `jj duplicate <id>` | Copy a commit elsewhere (git's cherry-pick equivalent) |

## Fork topology

See [jujutsu-vcs.fork.md](../../../docs/jujutsu-vcs.fork.md) for the `main`/`upstream` dual-parent
`@` topology, bookmark hygiene with `upstream-tip`/`fork-tip`, and
rebasing the fork merge after new upstream commits.

## Deep troubleshooting

For divergent changes, conflict markers (`??` bookmarks, 3-way conflicts), revset/fileset/template
syntax questions, or graph surgery beyond split/squash — the `jj-expert` subagent activates
automatically and has a full decision tree and git↔jj mapping reference.
