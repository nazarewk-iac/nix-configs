---
type: Solution
description: Solution for the jj workspaces convention — the shared jj repo config guard, the pinned devenv input, and the documented five-step procedure.
task: definition.md
authored_by: agent
timestamp: 2026-09-09T14:00:00+02:00
---

# Solution — jj workspaces for parallel sub-agent work

Task: [jj-workspaces-parallel-agents.md](definition.md).
Executable proof: [`checks/jj-experiments/test_workspaces.py`](../../../../checks/jj-experiments/test_workspaces.py).

## Root cause analysis

A `git worktree` is forbidden here because it is colocated: it shares one `.jj` store and one
working-copy commit with the trunk, so two writers race the same snapshot. On 2026-07-29 that race
truncated three files to 0 bytes. `jj workspace add` gives real isolation, but three separate
mechanisms made a naive workspace unsafe or unusable. Each one was measured, not inferred.

**1. The shared jj repo config.** `jj config path --repo` returns **the same absolute file** from the
trunk and from every workspace. The id in that path is not derived from any path: it is a random
value written once at `jj git init` into `.jj/repo/config-id`. Proof — `cat .jj/repo/config-id`
equals the path component byte-for-byte; moving a repo directory keeps the id; `jj git init` twice at
the same path yields two different ids. A secondary workspace reaches the same id through its
`.jj/repo` pointer file.

`modules/slots/jj/default.nix` `enterShell` wrote that path unconditionally. So a `devenv shell` in
a workspace retargeted the trunk's config. The severity depended on one git-ignored file:

| State | Generated config | Fork alias mentions |
|---|---|---|
| Trunk | 2568 B | 4 |
| Workspace **with** `devenv.slots.local.nix` | 2568 B | 4 |
| Workspace **without** it | 64 B (only the `"#schema"` line) | 0 |

The failure was silent because `devenv.nix:22` loads that file through
`lib.optional (builtins.pathExists ./devenv.slots.local.nix)`, which skips a missing file with no
warning. The trunk would lose `fork-tip`, `upstream-tip`, `fork-audit`, `sync-remotes`,
`sync-upstream`, `fork-help` and the `git.push` checks, with no message.

**2. No `.git` in a workspace.** `devenv.yaml` sets `inputs.nix-configs.url = git+file:.`. From a
workspace, Nix hands `file:.` to `git ls-remote`, which reads it as an scp-style remote and tries SSH
to a host literally named `file`. The error therefore looks like an auth problem and is not one.

**3. `path:` degradation.** `flake.nix`'s `nix-configs = self` does **not** fail the same way. Nix
silently degrades a bare `.` to a `path:` flake, and a `path:` flake copies git-ignored content into
the store. A probe with a 20 MiB git-ignored `.devenv/blob` produced a 21 MB store path containing
the blob. So `.#` in a workspace quietly copies the whole `.devenv/` tree.

## Solution

**Guard the shared config write, in the slot.** `modules/slots/jj/default.nix` `enterShell` now tests
for a **secondary** workspace before it writes:

```sh
if test -n "$_jj_root" && test -f "$_jj_root/.jj/repo"; then
  echo "kdn.jj: secondary jj workspace — the shared jj repo config stays untouched" >&2
elif test -n "$_jj_config_path"; then
  ln -sfn <generated> "$_jj_config_path"
fi
```

`.jj/repo` is a directory in the default workspace and a small pointer file in a secondary one. The
test asks for the secondary case on purpose: an unknown future jj layout then makes the shell write
the file, which is today's behaviour, and never makes the default workspace lose its config.

**Rejected: writing to `jj config path --workspace` instead.** That layer is genuinely per workspace,
so it looks like the root-cause fix, and it was the empirical agent's recommendation. It loses on two
counts. `test_fork_revset_aliases_resolve_from_a_workspace` proves a fresh workspace already resolves
`fork-tip` through the shared `--repo` layer *before* it runs any `devenv shell` — under
`--workspace` a new workspace would have no fork aliases when it needs them most. And the existing
`--repo` symlink would remain as a stale merging layer, so the change needs a migration. Nobody wants
per-workspace jj aliases; the sharing is a feature. Guard the write, keep the share.

**Pin the flake input, per workspace, in a git-ignored file.**

```yaml
# <workspace>/devenv.local.yaml
inputs:
  nix-configs:
    url: git+file:///Users/<you>/dev/github.com/nazarewk-iac/nix-configs?ref=<REV>&rev=<REV>
```

`<REV>` comes from `jj log -r 'fork-tip' --no-graph -T commit_id` in the trunk. devenv merges
`inputs:` from `devenv.local.yaml` last and it wins — `devenv-core/src/config.rs:14`, `:725`, and
`:727-745`.

`ref=` is **mandatory**. devenv rewrites the `locked` node, drops a lone `rev`, and defaults `ref` to
`master`, which this repo does not have: `revspec 'master' not found`. This corrects the URL form the
task file originally proposed.

**Documented the five-step procedure** in `docs/jujutsu-vcs.md` § "jj workspaces": create and
`jj new`; verify the isolation from both directories; `cp ../nix-configs/devenv.slots.local.nix .`;
write `devenv.local.yaml` and enter `devenv shell`; `jj workspace forget` plus `rm -rf`. Plus the
activation ban, the shared-config note, and hazard 3.

**Files changed**

| Path | Change |
|---|---|
| `modules/slots/jj/default.nix` | the `enterShell` guard, with the mechanism in a comment |
| `checks/jj-experiments/test_workspaces.py` | `test_secondary_workspace_is_detectable_from_the_filesystem` |
| `docs/jujutsu-vcs.md` | new § "jj workspaces", ~140 lines; the worktree section now points at it |
| `.agents/rules/jujutsu-vcs.md` | the five-step pointer and the activation ban in short form |
| `docs/vcs-workspaces.md` | hazard 3, the shared-config exception, a fourth checklist item |
| `AGENTS.md` | `docs/` table row for `docs/vcs-workspaces.md` |
| `docs/tasks/jj-workspaces-parallel-agents.md` | both decisions recorded, seven claims corrected |

## Verification steps

```bash
# the guard renders into the real enterShell
devenv eval 'enterShell'        # holds the `.jj/repo` test and the secondary-workspace message

# every workspace case passes, including the new one
nix run '.#jj-experiments-run' -- -k workspaces      # 17 passed, 93 deselected
```

Measured from a real probe workspace at `../.nix-configs--wsprobe`, created at `fork-tip`:

| Check | Result |
|---|---|
| `jj log -r @ -T change_id`, both dirs | `qolwvvnm…` against `kqutwywk…` — isolation real |
| `jj config path --repo`, both dirs | identical file |
| `jj config path --workspace`, both dirs | different files |
| `devenv info`, stock `devenv.yaml` | fails with the SSH-to-host-`file` error |
| `devenv eval 'claude.code.hooks.jj-guard'`, pinned | full hook attrset |
| `devenv build shell`, pinned | `/nix/store/…-devenv-shell` |
| `devenv shell -- <cmd>`, pinned | shell enters, exits 0; `DEVENV_ROOT` points at the workspace |
| the guard, in that same shell | message printed; shared config sha and 4 fork aliases unchanged |
| `devenv:git-hooks:run`, same shell | **fails** — `git rev-parse --show-toplevel` exit 128, no `.git` |
| unpinned URL against a dirty tracked file | evaluates the **uncommitted** value; `locked` holds nothing volatile |
| pinned URL against the same dirty file | evaluates the **committed** value; `locked` keeps `ref` only |
| `DEVENV_ROOT` / `DOTFILE` / `STATE` / runtime | all four differ from the trunk's |

The probe workspace was forgotten and removed, and the trunk's shared jj config was verified
byte-identical before and after (`sha256 7656a6c2…` both times).

## Follow-up notes

- **The guard is verified live, and so is the `git-hooks` failure.** A real `devenv shell` ran in a
  workspace on 2026-09-09. The guard printed its message and the shared jj config stayed
  byte-identical (`sha256 7656a6c2…`) with all 4 fork aliases. `git-hooks` fails harder than this
  file first claimed: `devenv:git-hooks:run` **fails** on `git rev-parse --show-toplevel` exit 128
  and cascades into `devenv:enterTest`. The shell still enters and exits 0. So a workspace runs no
  pre-commit checks — run the formatter and the linters from the trunk.
- **Still UNVERIFIED.** The claim that `jj workspace update-stale` has *exactly one* cause: jj
  0.45.1's help text names no condition and only the `op restore` case is proven. The
  `sha256(dotfile)[0:7]` formula for `devenv.runtime`; only the independence was measured. The real
  `.devenv/` size, so "hundreds of megabytes" stays a guess.
- **A locked 1Password breaks every `jj` command, not just a commit.** Hit during the workspace run:
  `SSH sign failed … 1Password: failed to fill whole buffer`, from a plain `jj log -r @`. The cause
  is that jj snapshots the working copy first, and the snapshot commit needs the signing key. Read
  the symptom as "the key is unavailable", never as workspace damage.
- **`devenv.lock` is tracked and devenv rewrites it in the workspace.** Confirmed unavoidable, now
  from source rather than by inference. `original` is written unstripped, so any url change lands in
  it; the staleness test is full JSON equality of the whole lock graph; validation runs
  unconditionally; and devenv has no `--frozen` / `--no-write-lock-file` equivalent. The convention
  says not to commit that change.
- **The trunk's rev-less `nix-configs` lock node is by design, not a procedure gap.** Nix strips
  every volatile attribute from a **local** input, and a git input is local when its url scheme is
  `file` — so `url: git+file:.` can never hold a rev. It cannot be stabilized by any command, flag or
  url form, because the strip sits in the serializer downstream of all of them. devenv depends on
  this (a local input must stay a live tree so the eval cache tracks edits) and ships the same shape
  for its own self-input. See the task file § "Why the trunk's own `nix-configs` lock node carries no
  rev".
- **One earlier measurement was wrong and is corrected.** This file's verification table previously
  said an unpinned `git+file:///<abs>` locks a `dirtyRev`. devenv records nothing volatile for either
  form. That observation came from a different writer, most likely Lix's `nix flake lock`. The
  conclusion it supported — the pin ignores the working tree, the unpinned form does not — is
  re-verified with devenv and stands.
- **The guard is not enforced.** Nothing stops a future edit from writing the shared path again. A
  `checks/` case that renders `enterShell` and greps for the test would close that.
- **jj 0.45.1 additions worth a look later:** `jj workspace rename`, and `jj workspace list -T
  <template>` over a `WorkspaceRef` type. No `is_current`-style template keyword exists, which is why
  the guard uses the filesystem rather than a template.
