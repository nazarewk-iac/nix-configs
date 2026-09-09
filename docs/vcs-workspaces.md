---
type: Reference
description: Gotchas when a background agent works in a jj-workspace-add sibling dir — stale DEVENV_ROOT, untracked-but-required files, and `path:` flakes copying git-ignored content.
timestamp: 2026-07-30T16:23:55+02:00
---

# Working in a sibling `jj workspace add` directory

> **See also:** [jujutsu-vcs.md](jujutsu-vcs.md) for the workspace mandate itself (why
> `jj workspace add --name <slug> ../.nix-configs--<slug>` is the *only* sanctioned parallel-isolation
> mechanism, why git-worktree corrupts the shared `.jj` store, and how to verify isolation is
> real). This doc covers two environment/tracking hazards that bite *after* you're set up in a
> sibling workspace — neither is a jj-mechanics bug; both are consequences of state that doesn't
> follow you into the sibling dir.

When a background agent works in a `jj workspace add` sibling directory (created OUTSIDE this
repo's tree, at `../.nix-configs--<slug>`), two things do **not** automatically follow it
into the workspace. Both surfaced during real use on 2026-07-30.

The examples below quote the observed output from that day, which still shows the older
`nix-configs-ws-<name>` path. The hazards do not depend on the directory name.

## Hazard 1 — `$DEVENV_ROOT` stays pinned to the main checkout

`$DEVENV_ROOT` (and the sibling `DEVENV_DOTFILE` / `DEVENV_STATE` / `DEVENV_PROFILE` / …) is
baked in at devenv **shell-entry time**. It does **not** track later `cd`s — including a `cd`
into a sibling workspace. So an agent whose shell was launched from the main checkout carries a
`$DEVENV_ROOT` still pointing at the **main** repo, no matter where it's actually working.

Why that's dangerous here: this repo defines a `PostToolUse:Bash` Claude Code hook in
`modules/slots/nix/default.nix`:

```nix
claude.code.hooks.git-hooks-run.command =
  ''cd "$DEVENV_ROOT" && ${lib.getExe config.git-hooks.package} run'';
```

It fires after **every** Bash tool call, unconditionally `cd`s to `$DEVENV_ROOT`, and runs
`prek run` (the git-hooks / pre-commit runner) there. From a sibling workspace that means
`prek run` executes against the **main** repo's git state on every single Bash command the
agent issues — regardless of which directory the agent is actually working in.

Observed failure: with the main checkout mid-git-operation (the user's live session), the two
racing writers collided on the shared colocated `.git`:

```
[cd "$DEVENV_ROOT" && prek run]: error: Failed to clean work tree
  caused by: Command `git write-tree` exited with an error:
fatal: Unable to create '/…/nix-configs/.git/index.lock': File exists.
Another git process seems to be running in this repository, or the lock file may be stale
```

This is structurally the same class of hazard as the git-worktree warning in
[jujutsu-vcs.md](jujutsu-vcs.md) (a background agent silently touching the main checkout's git
state), just introduced via an inherited env var instead of a colocated worktree. The lock
contention is timing-dependent, so *not* seeing it in one run does not mean it's safe.

**Fix / avoidance:**

- **Preferred:** have the sibling-workspace agent enter its **own** `devenv shell` from the
  workspace root, so every `DEVENV_*` var re-points at the workspace. This is the direction the
  user favors — sub-agents run their own devenv shell built from the correct root.
- **Or:** unset/override the inherited `DEVENV_*` vars before doing any work:
  ```bash
  env -u DEVENV_ROOT -u DEVENV_DOTFILE -u DEVENV_STATE -u DEVENV_PROFILE \
      -u DEVENV_RUNTIME -u DEVENV_TASK_FILE -u DEVENV_CMDLINE \
      devenv shell
  ```

## Hazard 2 — untracked-but-build-required files aren't snapshotted

`jj workspace add` only snapshots **tracked** content. Any file that's gitignored/untracked in
the main checkout is silently **absent** in the sibling workspace — even if a Nix build needs
it. Hit on 2026-07-30 as:

```
error: path '/…/nix-configs-ws-<name>/packages/jj-mcp/package-lock.json' does not exist
```

`packages/jj-mcp/default.nix` does `cp ${./package-lock.json} package-lock.json` at build time,
but that lockfile was gitignored — so it never carried into the sibling, breaking `devenv shell`
(which evaluates the `jj-mcp` package transitively).

**Fix:** track every file a build requires. This repo's `.gitignore` uses a
deny-everything-then-allow-list pattern; add the file via a sibling `.gitignore` next to it
(e.g. `packages/jj-mcp/.gitignore` with `!package-lock.json`). Devenv-generated symlinks
(`.claude/settings.json`, `.mcp.json`, `.pre-commit-config.yaml`) and `link-python`-style local
symlinks are *expected* to be regenerated per-workspace by `devenv shell` — those don't need
tracking, but they do reinforce that a sibling workspace needs its own `devenv shell` entry.

**One devenv-managed target is NOT per workspace:** the shared jj repo config at
`jj config path --repo`. It resolves to the same file from the trunk and from every workspace, so
the slot's `enterShell` symlink would write over the trunk's config. `modules/slots/jj/default.nix`
now guards that write. See [jujutsu-vcs.md](jujutsu-vcs.md) § "jj workspaces".

## Hazard 3 — `.#` in a workspace copies git-ignored content into the store

A workspace has no `.git`. Nix therefore cannot resolve a bare `.` as a git flake and degrades it
to a `path:` flake. A `path:` flake copies the **whole directory**, git-ignored files included.

Measured: a probe directory with a 20 MiB git-ignored `.devenv/blob`, named in `.gitignore`,
produced a 21 MB store path that **contained** the blob. So in a workspace every `nix build '.#…'`
and `nix eval '.#…'` copies the whole `.devenv/` tree once devenv has created it.

**Fix:** reference the trunk through the pinned input from
[jujutsu-vcs.md](jujutsu-vcs.md) § "jj workspaces" step 4, not through `.#`.

## Quick checklist before running agent work in a sibling workspace

1. `jj workspace list` shows more than one workspace, and `jj log -r @ -T change_id` differs
   between the two dirs (per [jujutsu-vcs.md](jujutsu-vcs.md)).
2. Enter a fresh `devenv shell` **from the workspace root** (re-points all `DEVENV_*`), or unset
   the inherited `DEVENV_*` vars.
3. Confirm every build-required file is tracked (no gitignored inputs to anything you'll build).
4. Use the pinned `devenv.local.yaml` input, not `.#` — otherwise a `path:` flake copies your whole
   `.devenv/` into the store (hazard 3).
