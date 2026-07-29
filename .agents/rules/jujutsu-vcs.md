---
type: Rule
description: "jj mandate: always use jj over git, working-copy conventions, non-interactive flags."
timestamp: 2026-07-09T15:32:54+02:00
---

# Jujutsu (jj) VCS

Full doc: [docs/jujutsu-vcs.md](../../docs/jujutsu-vcs.md) (fork topology:
[docs/jujutsu-vcs.fork.md](../../docs/jujutsu-vcs.fork.md)) — for practical command patterns
invoke the `jujutsu-vcs` skill. For deep troubleshooting (divergent changes, conflict markers,
graph surgery), the `jj-expert` subagent activates automatically.

**Always use `jj`, never raw `git`**, with two exceptions: `git push*` and read-only git
(`log`/`diff`/`show`/`status`/`remote`/`rev-parse`/`ls-files`). Everything else (commit, add,
checkout, reset, rebase, merge, stash, fetch, cherry-pick, branch/tag mutation) has a direct jj
equivalent. A `jj-guard` PreToolUse hook warns (but does not block) on most other raw `git` Bash
calls, but it is **not** the sole safeguard — it cannot intercept Claude Code's built-in `/commit`
slash command (which shells raw `git commit` internally); never use `/commit` in this repo.

> **`@` is a manually maintained convention, not an automatic behavior.** jj does not create a
> fresh empty `@` after `jj describe`/`jj commit` — you must run `jj new` yourself if you want
> that. Never pre-create a commit before making changes (no `jj new` as a checkpoint). Accumulate
> edits in `@`, then carve them out with `jj split -m 'msg' -- <files>` or fold them with
> `jj squash --from @ --into <target>`. Rebase is a last resort — only for genuine topology fixes
> or constructing a merge commit (`jj new <a> <b>`), never as routine work.

> **Non-interactive:** always pass `-m 'msg'` and `-- <files>` to `jj split`/`jj describe`/
> `jj squash` — they open an editor by default. `jj split` supports multiple `-- path1 path2 ...`.
> **Never `jj edit` to read a file** — use `jj file show --revision <id> <path>`.

> ⚠️ **BIG FAT WARNING — NEVER use a git worktree in this repo; parallel agents need a real jj
> workspace, created OUTSIDE this repo's tree, on a fresh change.**
> `git worktree` (which is what the Agent/Workflow tool's `isolation: "worktree"` option creates
> under the hood) is **colocated** — it registers under this repo's own `.git/worktrees/` and has
> **no `.jj` of its own**, so it shares the single `.jj` store with the main checkout. Running work
> there concurrently with the main working copy means two writers racing to snapshot the *same* jj
> change (`@`), and it **will** corrupt files: confirmed on 2026-07-29, a git worktree got created
> nested *inside* the repo tree at `.claude/worktrees/<name>/` while other work continued in the
> main checkout, and three just-edited files were silently truncated to 0 bytes from that race.
> Never call `git worktree` directly (it's blocked by `jj-guard` anyway) and never accept an
> Agent/Workflow `isolation: "worktree"` result at face value in this repo.
>
> If real filesystem isolation is genuinely needed for parallel work: use `jj workspace add
> <path>` — and **`<path>` must be a sibling directory OUTSIDE this repo's tree**
> (e.g. `../nix-configs-ws-<name>`), never nested under it (nesting risks the outer repo's file
> watchers/tools recursing into it, and is not what caused this incident but compounds the same
> class of hazard). `jj workspace add` gives a genuinely separate working copy — snapshot it with
> `jj new` immediately to start on a fresh change, never reusing the main working copy's change id.
> Verify isolation actually took with `jj workspace list` (must show more than one workspace) and
> by comparing `jj log -r @ --no-graph -T change_id` run from both directories — they must differ.
> If you can't confirm a distinct change id in a distinct workspace, do not run concurrent work —
> do it sequentially in the main working copy instead.

- **Always leave an empty `jj` change on top** when finishing work — gives the user a clean
  working copy to review from.
- **NEVER push changes** — the user reviews and pushes.
- Use conventional commit format (`feat:`, `docs:`, `chore:`, `fix:`).
