# Jujutsu (jj) VCS

Full doc: [docs/jujutsu-vcs.md](../../docs/jujutsu-vcs.md) (fork topology:
[docs/jujutsu-vcs.fork.md](../../docs/jujutsu-vcs.fork.md)) — for practical command patterns
invoke the `jujutsu-vcs` skill. For deep troubleshooting (divergent changes, conflict markers,
graph surgery), the `jj-expert` subagent activates automatically.

**Always use `jj`, never raw `git`**, with two exceptions: `git push*` and read-only git
(`log`/`diff`/`show`/`status`/`remote`/`rev-parse`/`ls-files`). Everything else (commit, add,
checkout, reset, rebase, merge, stash, fetch, cherry-pick, branch/tag mutation) has a direct jj
equivalent. A `jj-guard` PreToolUse hook blocks most other raw `git` Bash calls, but it is **not**
the sole safeguard — it cannot intercept Claude Code's built-in `/commit` slash command (which
shells raw `git commit` internally); never use `/commit` in this repo.

> **`@` is a manually maintained convention, not an automatic behavior.** jj does not create a
> fresh empty `@` after `jj describe`/`jj commit` — you must run `jj new` yourself if you want
> that. Never pre-create a commit before making changes (no `jj new` as a checkpoint). Accumulate
> edits in `@`, then carve them out with `jj split -m 'msg' -- <files>` or fold them with
> `jj squash --from @ --into <target>`. Rebase is a last resort — only for genuine topology fixes
> or constructing a merge commit (`jj new <a> <b>`), never as routine work.

> **Non-interactive:** always pass `-m 'msg'` and `-- <files>` to `jj split`/`jj describe`/
> `jj squash` — they open an editor by default. `jj split` supports multiple `-- path1 path2 ...`.
> **Never `jj edit` to read a file** — use `jj file show --revision <id> <path>`.

- **Always leave an empty `jj` change on top** when finishing work — gives the user a clean
  working copy to review from.
- **NEVER push changes** — the user reviews and pushes.
- Use conventional commit format (`feat:`, `docs:`, `chore:`, `fix:`).
