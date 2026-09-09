---
type: Reference
description: What test_workspaces.py proves about jj workspaces as the isolation mechanism for parallel agent work, and the three hazards a workspace introduces.
timestamp: 2026-09-09T00:00:00+02:00
authored_by: agent
---

# jj workspaces — test notes

Paired file: [`test_workspaces.py`](test_workspaces.py).

Task and convention: [`docs/tasks/jj-workspaces-parallel-agents.md`](../../docs/tasks/2026-09/jj-workspaces-parallel-agents/definition.md).

## Why this group exists

A parallel sub-agent needs its own working copy of this repo. A `git worktree` cannot supply one.
A `git worktree` is **colocated**: it registers under the repo's own `.git/worktrees/`, it holds no
`.jj` of its own, and it therefore shares one `.jj` store **and one working-copy commit** with the
trunk checkout. Two writers then snapshot the same file set. On 2026-07-29 that race truncated
three files to 0 bytes.

`jj workspace add` gives a real second working copy: a second working-copy commit, a second
`.jj/working_copy` state dir, one shared store. This group proves the properties that claim rests
on, and it pins down the three hazards a workspace does introduce.

All measurements come from jj 0.44.0.

## 1. Structural isolation

| Test | Claim |
|---|---|
| `test_workspace_has_own_jj_and_no_git` | The workspace has its own `.jj/working_copy`. `.jj/repo` is a plain text file that holds a **relative** path to the trunk's `.jj/repo`, resolved against the workspace's own `.jj` dir. The workspace has **no `.git`**. The trunk's `.git/worktrees/` stays empty. |
| `test_workspace_sits_outside_the_repo_tree` | The workspace dir is a sibling of the repo dir, named `.<repo-dir>--<slug>`. The repo dir is not one of its parents. |
| `test_workspace_change_id_differs_from_trunk` | Each workspace owns a distinct `@`. The two new commits are siblings: both have the same parent, so neither rewrites the other's history. |
| `test_workspace_add_accepts_a_base_revision` | `-r <rev>` puts the workspace `@` on a chosen base. |
| `test_nested_dir_resolves_to_the_enclosing_workspace` | `jj` run from a subdirectory of the workspace resolves to the workspace, never to the trunk. |
| `test_untracked_file_does_not_travel_into_a_workspace` | A fresh workspace holds tracked files only. Every git-ignored file is absent. |

The empty `.git/worktrees/` assertion is the point of the whole group. It is the single mechanical
difference from the forbidden mechanism.

## 2. Concurrent writes

`test_concurrent_snapshots_do_not_lose_content` runs 15 rounds in each of two workspaces at the
same time. Each round writes a 4 KiB file and then runs `jj status`, which snapshots. After each
snapshot the test reads the file back and compares it byte for byte. The result:

- no truncation and no partial write,
- no `jj status` failure,
- neither working copy adopts the other's file,
- `divergent()` stays empty,
- both `@` change ids are unchanged.

`test_concurrent_commits_land_in_separate_changes` runs two `jj` commit sequences in parallel. Both
commits survive in the shared store. jj reconciles the two concurrent operations in the op log by
itself; the test needs no lock and no retry.

## 3. Lifecycle

| Test | Claim |
|---|---|
| `test_forget_then_remove_directory` | `jj workspace forget <name>` drops the record and leaves the files. Removing the dir afterwards is safe. |
| `test_remove_directory_then_forget` | The reverse order also works. The trunk keeps working with a dangling record; `forget` then cleans it. |
| `test_op_restore_makes_another_workspace_stale` | A repo-wide op-log rewind (`jj op restore`) from the trunk makes the other workspace stale. `jj workspace update-stale` recovers it. |

The stale case needed a real rewind to reproduce. An ordinary rewrite of the other workspace's `@`
(a `describe`, a `squash`, an `abandon`) does **not** make it stale — jj 0.44 recovers on its own.
Only a repo-wide operation that moves the op head below the workspace's recorded working-copy
operation does. `jj op restore` is the one such command an agent may plausibly run.

## 4. Shared config — hazard 1

`test_repo_config_is_shared_and_workspace_config_is_not` proves the split:

| Scope | Path | Shared? |
|---|---|---|
| `jj config path --repo` | `$XDG_CONFIG_HOME/jj/repos/<hash>/config.toml` | **Yes** — one file for the trunk and every workspace |
| `jj config path --workspace` | `$XDG_CONFIG_HOME/jj/workspaces/<hash>/config.toml` | No — one file per workspace |

`modules/slots/jj/default.nix` `enterShell` runs `ln -sfn <generated> "$(jj config path --repo)"`.
That target is the **shared** file. A `devenv shell` in a workspace therefore rewrites the trunk's
repo config too. When the workspace has no `devenv.slots.local.nix`, the generated file shrinks to a
stub, and the fork revset aliases plus the push checks disappear from the trunk with no warning.

`test_repo_config_overwrite_from_workspace_strips_trunk_aliases` reproduces the failure directly: it
writes a stub over the shared path from the workspace, then shows the trunk can no longer read a
repo-scope revset alias it set earlier.

The mitigation is the mandatory bootstrap step in the task file: copy `devenv.slots.local.nix` into
the workspace **before** the first `devenv shell` there.

## 5. Fork revset aliases

`test_fork_revset_aliases_resolve_from_a_workspace` builds the standard base topology, adds a
workspace, and asserts `fork-tip` and `upstream-tip` resolve to the same commits from both
directories. They must: both handles read one store. The test also confirms the topology labels
still hold from the workspace (`upstream-tip` = `U2`, `fork-tip` = `M`).

`test_workspace_add_does_not_move_the_fork_tips` asserts the tips are unchanged after the workspace
is added. The new empty workspace commit is a sibling of the trunk's own empty `@`, so it does not
become a tip.

Both tests need `JJ_FORK_CONFIG_TOML`, so they skip outside the devenv shell and the check
derivation.

## 6. Naming

`test_workspace_list_reports_every_workspace` adds three workspaces and asserts every change id is
distinct. It also fixes the naming rule in code: `Repo.workspace_add` always passes `--name <slug>`,
because jj takes the default workspace name from the destination basename and that basename starts
with a dot.

## Hazards this group does not test

Two findings are outside the reach of a jj-only harness. They are recorded in the task file:

1. **`git+file:.` needs a `.git`.** `devenv.yaml` sets `inputs.nix-configs.url = git+file:.`, and
   `flake.nix` sets `nix-configs = self`. A workspace has no `.git`, so both fail there.
   `path:.` is not a substitute: it includes git-ignored files, and `.devenv/` alone is hundreds of
   megabytes. The mitigation is an absolute pinned reference to the trunk,
   `git+file:///<trunk>?rev=<commit>`.
2. **devenv state is per-directory.** `DEVENV_DOTFILE` is `DEVENV_ROOT + "/.devenv"`, `DEVENV_STATE`
   is `DEVENV_DOTFILE + "/state"`, and the runtime dir is
   `<XDG_RUNTIME_DIR or /tmp>/devenv-<sha256(dotfile)[0:7]>`. Two directories therefore get two
   independent devenv states, including the runtime socket dir. Only the Nix daemon store and
   `~/.cache/nix` are shared, and both are already concurrency-safe.

## Helpers added to `conftest.py`

| Helper | Purpose |
|---|---|
| `Repo.workspace_add(name, *, revision=None)` | Adds a workspace at `<parent>/.<repo-dir>--<name>` and returns a `Repo` handle for it. The handle shares `env`, `cfg`, and `harness`, so `Harness.cleanup` removes the dir. Its timestamp counter starts 1000 steps ahead, so two handles never stamp one time twice. |
| `Repo.workspace_list()` | Returns `{workspace name: change id of that workspace's @}`. |
| `Repo.workspace_forget(name)` | Drops a workspace record. Leaves the dir. |
| `Repo.workspace_root(*, cwd=None)` | Returns the workspace root jj resolves from `cwd`. |
| `Repo.op_id()` | Returns the operation head id. Uses `--ignore-working-copy`, so the query adds no operation. |
| `Repo.jj(..., cwd=None)` | New keyword. Defaults to the repo dir, so every existing call is unchanged. |

## How to run

```bash
nix run '.#jj-experiments-run' -- -k workspaces -v
# or, inside checks/jj-experiments:
devenv shell
pytest -k workspaces -v
```
