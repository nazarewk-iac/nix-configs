---
type: Rule
description: "jj mandate: use jj over git, working-copy conventions, non-interactive flags."
timestamp: 2026-07-31T14:00:00+02:00
---

# Jujutsu (jj) VCS

Full doc: [docs/jujutsu-vcs.md](../../docs/jujutsu-vcs.md) (fork topology:
[docs/jujutsu-vcs.fork.md](../../docs/jujutsu-vcs.fork.md)). For practical command patterns,
invoke the `jujutsu-vcs` skill. For deep troubleshooting (divergent changes, conflict markers,
graph surgery), the `jj-expert` subagent activates on its own.

**Always use `jj`, never raw `git`**, with two exceptions: `git push*` and read-only git
(`log`/`diff`/`show`/`status`/`remote`/`rev-parse`/`ls-files`). Everything else (commit, add,
checkout, reset, rebase, merge, stash, fetch, cherry-pick, branch/tag mutation) has a direct jj
equivalent. A `jj-guard` PreToolUse hook warns (but does not block) on most other raw `git` Bash
calls. It is **not** the sole safeguard — it cannot intercept Claude Code's built-in `/commit`
slash command, which shells raw `git commit` internally. Never use `/commit` in this repo.

> **`@` is a manual convention, not an automatic behavior.** jj does not create a fresh empty `@`
> after `jj describe`/`jj commit` — run `jj new` yourself when you want that. Do NOT create a
> commit before you make changes (no `jj new` as a checkpoint). Let edits accumulate in `@`, then
> carve them out with `jj split -m 'msg' -- <files>` or fold them with `jj squash --from @ --into
> <target>`. Rebase is a last resort — use it only for a genuine topology fix or to construct a
> merge commit (`jj new <a> <b>`), never as routine work.

> **The empty change on top is for wrap-up only.** Run `jj new` to leave an empty `@` **only when
> you finish described work**, so the user gets a clean working copy to review from. Do NOT stack
> an empty change above undescribed or parked work — that buries the working copy one level down.
> When you park work, keep `@` on the parked change itself. Never leave an undescribed change in
> the middle of the graph as a container or a checkpoint. `jj split` already creates the
> follow-on change for you; you do not add one by hand.

> **Non-interactive:** always pass `-m 'msg'` and `-- <files>` to `jj split`/`jj describe`/
> `jj squash` — they open an editor by default. `jj split` accepts multiple `-- path1 path2 ...`.
> **Never `jj edit` to read a file** — use `jj file show --revision <id> <path>`.

> **Never redirect into the file a `jj` read is reading.** `jj file show -r <rev> x | … > x`
> truncates `x` **before** the read starts. `jj file show` then snapshots the empty file into `@`,
> and jj rebases that empty file into every descendant — so the read returns nothing and the file
> is lost at several revisions. Measured on 2026-09-09 with `devenv.lock`; `jj op restore
> <op-before-the-snapshot>` recovered it. Write to a temporary file, then `mv`. The same rule
> covers `jj diff`, `jj show` and `jj file list`.

> ⚠️ **BIG FAT WARNING — NEVER use a git worktree in this repo. A parallel agent needs a real jj
> workspace, created OUTSIDE this repo's tree, on a fresh change.**
> `git worktree` (what the Agent/Workflow tool's `isolation: "worktree"` option creates under the
> hood) is **colocated** — it registers under this repo's own `.git/worktrees/` and has **no `.jj`
> of its own**, so it shares the single `.jj` store with the main checkout. Concurrent work there
> means two writers race to snapshot the *same* jj change (`@`), and it **will** corrupt files.
> Confirmed on 2026-07-29: a git worktree was created nested *inside* the repo tree at
> `.claude/worktrees/<name>/` while other work continued in the main checkout, and three
> just-edited files were truncated to 0 bytes from that race. Never call `git worktree` directly
> (`jj-guard` blocks it anyway). Never accept an Agent/Workflow `isolation: "worktree"` result at
> face value in this repo.
>
> When parallel, filesystem-isolated work is genuinely needed: use
> `jj workspace add --name <slug> -r <base-rev> <path>`. The `<path>` **must be a sibling directory
> OUTSIDE this repo's tree**, and the convention is `../.<repo-dir>--<slug>` — for this repo,
> `../.nix-configs--<slug>`. Never nest it under the repo. A nested path risks the outer repo's file
> watchers/tools recursing into it. Always pass `--name <slug>`, because `jj workspace add` otherwise
> takes the workspace name from the destination basename and the leading dot goes into the name.
> `jj workspace add` gives a genuinely separate working copy.
> Snapshot it with `jj new` at once to start on a fresh change. Never reuse the main working
> copy's change id. Verify the isolation with `jj workspace list` (it must show more than one
> workspace) and compare `jj log -r @ --no-graph -T change_id` from both directories — they must
> differ. When you cannot confirm a distinct change id in a distinct workspace, do not run
> concurrent work — do it in sequence in the main working copy instead.
>
> **Read [docs/jujutsu-vcs.md](../../docs/jujutsu-vcs.md) § "jj workspaces" before you create one.**
> The creation command is one of five steps. Two more stop a silent failure: `cp
> ../nix-configs/devenv.slots.local.nix .` (a fresh workspace holds tracked files only, and
> `devenv.nix` skips the missing file with no warning), and a git-ignored `devenv.local.yaml` that
> repoints `inputs.nix-configs` at the trunk with `?ref=<REV>&rev=<REV>` (a workspace has no
> `.git`, so `git+file:.` cannot resolve). Do not commit the `devenv.lock` change that follows.
> Expect `devenv:git-hooks:run` to **fail** in every workspace shell (no `.git` to install into).
> The shell still enters and exits 0, so that failure is normal — but a workspace runs no
> pre-commit checks, so run the formatter and the linters from the trunk.
>
> **A workspace evaluates, builds and tests. It NEVER activates.** No `switch`/`boot`/`test`, no
> `home-manager switch`, nothing that needs sudo to change the running system, and no
> `git push` / `jj git push` / `jj sync-remotes` / `jj bookmark set`. Activation is machine-global,
> so a workspace would silently overwrite whatever the trunk activated. A `switch` and a push are
> always the user's call, from the trunk.

- **Leave an empty `jj` change on top only when you wrap up finished, described work** — it gives
  the user a clean working copy to review from. Do NOT stack one above undescribed or parked work.
- **NEVER push changes** — the user reviews and pushes.
- Use conventional commit format (`feat:`, `docs:`, `chore:`, `fix:`).
