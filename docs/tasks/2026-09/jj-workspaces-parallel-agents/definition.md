---
type: Task
description: Adopt jj workspaces as the sanctioned isolation mechanism for parallel sub-agent work, with a sibling naming convention, a mandatory bootstrap step, and a ban on system activation from a workspace.
status: done
solution: jj-workspaces-parallel-agents.done.md
authored_by: agent
timestamp: 2026-09-09T00:00:00+02:00
---

# jj workspaces for parallel sub-agent work

Evidence: [`checks/jj-experiments/test_workspaces.py`](../../../../checks/jj-experiments/test_workspaces.py)
and its prose file [`test_workspaces.md`](../../../../checks/jj-experiments/test_workspaces.md).

## Goal

Give a parallel sub-agent a real, filesystem-isolated working copy of this repo.

A `git worktree` is forbidden. It is **colocated**: it registers under this repo's own
`.git/worktrees/`, it holds no `.jj` of its own, and it therefore shares one `.jj` store **and one
working-copy commit** with the trunk checkout. Two writers snapshot the same file set. On
2026-07-29 that race truncated three just-edited files to 0 bytes. The Agent tool's
`isolation: "worktree"` option creates exactly this, so it stays forbidden here.

`jj workspace add` is the replacement. The test group proves it is safe: distinct working-copy
commits by construction, per-workspace `working_copy` state, an op log that jj reconciles by itself,
and 30 concurrent snapshots with no truncation, no loss, and no divergent commit.

This task turns the replacement into a written convention.

## Naming convention

A workspace lives in a **sibling** directory of the repo:

```
~/dev/github.com/nazarewk-iac/nix-configs/            # trunk checkout
~/dev/github.com/nazarewk-iac/.nix-configs--<slug>/   # workspace
```

- Pattern: `../.<repo-dir>--<slug>/`.
- `<slug>` is a short kebab-case task name, for example `ssh-scoping` or `flake-update`.
- The path must be **outside** the repo tree. A nested path risks the outer repo's file watchers and
  tools recursing into it.
- **Verdict on the leading dot: keep it.** It helps more than it costs. `fd`, `rg`, and most editor
  scans skip a hidden directory by default, so the sibling never shows up in a search of the parent
  directory. The one cost: `jj workspace add` takes the default workspace name from the destination
  basename, so the name would become `.nix-configs--<slug>`. Always pass `--name <slug>`.

Creation:

```bash
jj workspace add --name <slug> -r <base-rev> ../.nix-configs--<slug>
```

Verify the isolation from **both** directories before any work starts:

```bash
jj log -r @ --no-graph -T change_id     # the two values MUST differ
jj workspace list                       # MUST show more than one workspace
```

Cleanup, either order:

```bash
jj workspace forget <slug>
rm -rf ../.nix-configs--<slug>
```

`jj workspace update-stale` recovers a stale workspace. A repo-wide op-log rewind (`jj op restore`)
run from another workspace is the one condition known to produce one. An ordinary rewrite of the
workspace's `@` does not — jj recovers on its own.

**"Exactly one condition" is UNVERIFIED.** On jj 0.45.1 the `jj workspace --help` text names no
condition and only links `https://docs.jj-vcs.dev/latest/working-copy/#stale-working-copy`. The
`op restore` case is proven by `test_op_restore_makes_another_workspace_stale`; no measurement rules
out a second cause.

## Bootstrap step — mandatory

A fresh workspace holds **tracked files only**. Every git-ignored file is absent. One of them is
load-bearing:

```bash
cp ../nix-configs/devenv.slots.local.nix .
```

This is not optional, and the reason is a real hazard, not tidiness. `jj config path --repo`
resolves to **one shared file** for the trunk and every workspace.
`modules/slots/jj/default.nix` `enterShell` runs
`ln -sfn <generated> "$(jj config path --repo)"`. A `devenv shell` in a workspace with no
`devenv.slots.local.nix` therefore writes a stub over the shared file and strips the fork revset
aliases and the push checks **from the trunk as well**.

**The mechanism of the silence, measured:** `devenv.nix:22` loads the file through
`lib.optional (builtins.pathExists ./devenv.slots.local.nix)`. A missing file is skipped, with no
warning and no error. The slot settings then collapse to their defaults, `kdn.jj.fork.enable` turns
off, and the generated config shrinks to a 64-byte stub.

`jj config path --workspace` is per workspace, so it is unaffected.

Checklist item 2 now also guards the write in the slot itself, so the copy is no longer the only
protection. Keep the copy anyway — `devenv.slots.local.nix` carries every other slot setting too.

Do **not** copy anything else. `.devenv/`, `.direnv/`, `.pre-commit-config.yaml`,
`.claude/settings.json`, `.agents/skills/`, and every `/nix/store` symlink regenerate on the first
`devenv shell` in the workspace.

## Hazard: a workspace has no `.git`

A workspace directory holds `.jj` and no `.git` at all. Consequences, as measured on
jj 0.45.1 / devenv 2.2.3:

1. `devenv.yaml` sets `inputs.nix-configs.url = git+file:.`. That literal string cannot resolve
   from a workspace. Nix hands `file:.` to `git ls-remote`, which reads it as an scp-style remote
   and tries SSH to a host named `file`:
   ```
   ssh: Could not resolve hostname file: nodename nor servname provided, or not known
     × Lock validation failed:
            … while fetching the input 'git+file:.'
   ```
   The failure comes from devenv's own bootstrap resolver,
   `<workspace>/.devenv/bootstrap/resolve-lock.nix:84`.
2. `flake.nix`'s `nix-configs = self` does **NOT** fail. **Correction, measured 2026-09-09:** an
   earlier version of this section claimed both fail. Without a `.git`, Nix silently degrades a
   bare `.` to a `path:` flake and `self` becomes that path flake. From a workspace,
   `nix flake metadata .` exits 0 with `resolvedUrl = path:/…/.nix-configs--<slug>`, and
   `nix eval '.#packages.aarch64-darwin.kdn-nix-fmt.drvPath'` succeeds. Only the explicit
   `git+file:.` string cannot degrade.
3. The git-hooks install task has no repo to install into. **VERIFIED 2026-09-09** by a real
   `devenv shell` entry in a workspace. It is not a silent skip — the devenv task fails and the
   failure cascades:
   ```
   WARNING: git-hooks.nix: skipping hook installation: fatal: not a git repository
   error: Command `git rev-parse --show-toplevel` exited with an error: exit status: 128
   ✖ Running devenv:git-hooks:run in 881ms (failed)
   ✖ Running devenv:enterTest in 334ns (dependency failed)
   ✖ Running tasks in 5.16s (failed)
   ```
   The shell still enters and `devenv shell -- <cmd>` exits 0, so the failure is loud but not
   blocking. `.pre-commit-config.yaml` is still symlinked and `prek` is still on `PATH`; they have
   no repo to act on. Consequence for the convention: a workspace runs **no** pre-commit checks, so
   the formatter and the linters must run from the trunk before a commit.

`path:` is not a substitute, but it is also not a choice. It is what a workspace **gets
automatically** for any `.#` reference, and it copies git-ignored content into the store.
Measured: a probe with a 20 MiB git-ignored `.devenv/blob`, named in `.gitignore`, produced a
21 MB store path that contained the blob. So every `nix build '.#…'` in a workspace copies the
whole `.devenv/` tree once devenv has created it. The earlier claim "`.devenv/` alone is hundreds
of megabytes" stays **UNVERIFIED** — the real directory was never measured.

## devenv independence

devenv state is per-directory, so a workspace and the trunk do not collide:

| devenv value | Definition | Independent? |
|---|---|---|
| `DEVENV_ROOT` | the shell's directory | yes |
| `DEVENV_DOTFILE` | `DEVENV_ROOT + "/.devenv"` | yes |
| `DEVENV_STATE` | `DEVENV_DOTFILE + "/state"` | yes |
| `devenv.runtime` | `<XDG_RUNTIME_DIR or /tmp>/devenv-<hash>` | yes — measured `/tmp/devenv-18f6d5f` (trunk) against `/tmp/devenv-34e4006` (workspace); the `sha256(dotfile)[0:7]` formula itself is UNTESTED |
| `PREK_HOME`, `devenv.local.yaml`, git hooks | under `DEVENV_ROOT` | yes |
| Nix daemon store, `~/.cache/nix` | machine-global | shared, and already concurrency-safe |

Two `devenv shell` sessions, one per directory, therefore run with separate state including separate
runtime socket dirs.

## Prohibition: a workspace never activates a system

**A workspace evaluates, builds, and tests. It never activates.**

The reason is that activation is machine-global, not directory-scoped. `darwin-rebuild switch` and
`nixos-rebuild switch` replace the machine's current system profile, write to `/run/current-system`,
restart services, and mutate `/etc`. Two workspaces cannot each hold a different "current system".
A `switch` from a workspace silently overwrites whatever the trunk (or another workspace) activated,
and the trunk has no way to detect it. A parallel agent has no mandate to change the machine.

Allowed from a workspace:

```bash
nix build ...
nix eval ...
nix flake check
nix run '.#darwin-rebuild' -- build
./nixos-rebuild.sh build
devenv shell / devenv eval / devenv build shell
pytest, formatters, linters
```

Forbidden from a workspace:

```bash
nix run '.#darwin-rebuild' -- switch     # and any remote= variant
./nixos-rebuild.sh switch
darwin-rebuild switch / nixos-rebuild switch / boot / test
home-manager switch
anything that needs sudo to change the running system
git push / jj git push / jj sync-remotes / jj bookmark set
```

A `switch` is always the user's call, from the trunk.

## Checklist

### 1. Document the convention

- [x] Add a `jj workspaces` section to `docs/jujutsu-vcs.md`: the naming convention, the creation
      command, the verify step, the bootstrap step, the cleanup step, and the hazards above.
      Done 2026-09-09: § "jj workspaces: the sanctioned parallel-isolation mechanism", with the
      five steps, the `devenv.local.yaml` pin, the shared-config guard, and the activation ban.
- [x] Replace the `../nix-configs-ws-<name>` guidance in `.agents/rules/jujutsu-vcs.md` with a
      pointer to that section, plus the naming pattern and the activation prohibition in short form.
      Done 2026-09-09: the rule file, `docs/jujutsu-vcs.md` and `docs/vcs-workspaces.md` all name
      `../.nix-configs--<slug>` and the mandatory `--name <slug>`. The activation prohibition is
      still only in this task file — item 1's first box owns that move.
- [x] Add the doc row to the `docs/` table in `CLAUDE.md`. Done 2026-09-09 in `AGENTS.md` —
      `CLAUDE.md` is a symlink to it. Added a row for `docs/vcs-workspaces.md` and named the
      workspace convention in the `docs/jujutsu-vcs.md` row.

### 2. Guard the shared jj repo config

- [x] **Decision, 2026-09-09: add the guard. The bootstrap copy alone is not enough.**
      Implemented in `modules/slots/jj/default.nix` `enterShell`.

**The hazard is real and quantified.** `jj config path --repo` returns the same absolute file from
the trunk and from a workspace. The generated config in three states:

| State | Size | `fork-tip` / `upstream-tip` mentions |
|---|---|---|
| Trunk, live symlink target | 2568 B | 4 |
| Workspace **with** `devenv.slots.local.nix` | 2568 B | 4 |
| Workspace **without** it | **64 B** | **0** |

The 64-byte stub holds only the `"#schema"` line. A bootstrap-less `devenv shell` in a workspace
therefore strips `revset-aliases.fork-tip`, `revset-aliases.upstream-tip`, `aliases.fork-audit`,
`aliases.sync-remotes`, `aliases.sync-upstream`, `aliases.fork-help` and the `git.push` checks
**from the trunk**.

**Why the bootstrap copy is not sufficient:** even with the file, the workspace's generated store
path differs from the trunk's, because the embedded `doc=` path differs. So a workspace shell always
retargets the trunk's symlink. With the copy the damage is cosmetic; without it the trunk loses the
fork tooling. The copy downgrades a silent breakage to a silent retarget. It does not remove it.

**The guard, and why it tests for SECONDARY rather than for default:**

```sh
if test -n "$_jj_root" && test -f "$_jj_root/.jj/repo"; then
  echo "kdn.jj: secondary jj workspace — the shared jj repo config stays untouched" >&2
elif test -n "$_jj_config_path"; then
  ln -sfn <generated> "$_jj_config_path"
fi
```

`.jj/repo` is a **directory** in the default workspace and a small **pointer file** in a secondary
one. The test asks whether this is a secondary workspace, so an unknown future jj layout makes the
shell write the file — today's behaviour — and never makes the default workspace lose its config.
That is the safe fail direction. New case:
`test_secondary_workspace_is_detectable_from_the_filesystem`.

**Rejected alternative: write to `jj config path --workspace` instead.** That layer is genuinely per
workspace (verified: an alias written there resolves in that workspace and errors in the default
one), so it looks like the root-cause fix. It loses on two counts:

1. **It drops a benefit that is already proven and used.**
   `test_fork_revset_aliases_resolve_from_a_workspace` shows a fresh workspace resolves `fork-tip`
   and `upstream-tip` through the shared `--repo` layer, before it ever runs `devenv shell`. Under
   `--workspace` a new workspace would have no fork aliases until its own shell built, and its first
   command is often exactly `jj log -r fork-tip`.
2. **It needs a migration.** The existing `--repo` symlink would stay and keep merging as a stale
   layer, so the change would have to delete it.

Nobody wants per-workspace jj aliases, so the sharing is a feature. Guard the write; keep the share.

**What the `<hash>` in the config path is keyed on — measured, since this was the open question.**
It is a **random value written once at `jj git init`** and persisted in `.jj/repo/config-id`. It is
not derived from the repo path, the workspace path, or a store path. Evidence: `cat
.jj/repo/config-id` equals the path component byte-for-byte; moving a repo directory keeps the id;
`jj git init` twice at the same path yields two different ids. A secondary workspace reaches the
same id through its `.jj/repo` pointer file. `jj workspace add` pre-creates the
`~/.config/jj/workspaces/<id>/` directory, so a guard needs no `mkdir -p`.

### 3. Decide the `git+file:` mitigation

- [x] **Decision, 2026-09-09: a git-ignored `devenv.local.yaml` in the workspace, with `ref` AND
      `rev` both set to the same commit id.** The trunk's `devenv.yaml` is unchanged.

```yaml
inputs:
  nix-configs:
    url: git+file:///Users/<you>/dev/github.com/nazarewk-iac/nix-configs?ref=<REV>&rev=<REV>
```

`<REV>` comes from `jj log -r 'fork-tip' --no-graph -T commit_id`, run in the trunk.

devenv merges `inputs:` from `devenv.local.yaml` last, and it wins — confirmed in the devenv source
at `devenv-core/src/config.rs:14`, `:725` (`// Load devenv.local.yaml last (if it exists) to allow
local overrides`) and `:727-745`.

Verified end to end from a workspace: `devenv eval 'name'` → `{"name": "devenv-shell"}`;
`devenv eval 'claude.code.hooks.jj-guard'` → the full hook attrset, so the slots tree evaluated;
`devenv build shell` → a `devenv-shell` store path.

**`ref=` is mandatory. A bare `rev=` fails.** **This corrects the URL form this task file proposed
earlier** (`?rev=<commit-id>` alone). The root cause is now traced to source, not just observed.
Nix strips `rev`, `narHash`, `lastModified`, `revCount`, `dirtyRev` and `dirtyShortRev` from the
`locked` node of any input it considers **local**, and a git input is local when its url scheme is
`file`. See `src/libflake/lockfile.cc`, whose comment reads "Strip volatile attributes from local
inputs to avoid lock file churn. Local inputs are always fetched fresh", and `isLocal` in
`src/libfetchers/git.cc`. So `ref` is the only pin that survives into `locked`. With no `ref`,
devenv falls back to a default branch and this repo has no `master`:
`error: resolving Git reference 'master': revspec 'master' not found`.

**The pin does remove the `prek` / `git write-tree` re-snapshot race — re-verified 2026-09-09 with
devenv itself.** A probe dependency repo at `v1-COMMITTED`, then modified to
`v2-DIRTY-UNCOMMITTED` without a commit:

| URL | `locked` | evaluated value |
|---|---|---|
| unpinned `git+file:///<abs>` | `{type, url}` — nothing volatile at all | `"v2-DIRTY-UNCOMMITTED"` |
| `?ref=<REV>&rev=<REV>` | `{ref: <REV>, type, url}` — `rev` stripped | `"v1-COMMITTED"` |

**This corrects the `locked` column of the earlier version of this table**, which claimed the
unpinned form records `dirtyRev` and the pinned form keeps `rev` and a narHash. Neither is true of
devenv: it records nothing volatile for either form. That earlier observation came from a different
writer — most likely Lix's own `nix flake lock`, which has no such strip step. The behavioural
conclusion is unchanged and now rests on devenv's own output.

**Runner-up: `devenv -o nix-configs '<url>' <subcommand>`** (`devenv/src/cli.rs:433-439`, a global
option). It works and locks the same node. It lost because it must be typed on **every** devenv
invocation: a bare `devenv eval` fails even when `devenv.lock` already holds the pinned node, since
devenv validates `locked.original` against `devenv.yaml` and refetches on a mismatch. Every
wrapper, `direnv` hook and editor integration would need the flag, and a missed one fails with the
confusing SSH-to-host-`file` error. It is also less discoverable than a file in the workspace.

**Third place: unpinned absolute `git+file:///<abs-path>`.** It evaluates and builds, but its
`locked` node holds no `rev`, so Nix re-reads the trunk's working tree and index on every
evaluation. That is the race the pin exists to remove.

**Cost to write into the convention:** both mechanisms rewrite the **tracked** `devenv.lock` in the
workspace (`jj status` → `M devenv.lock`). The agent must not commit that change.
`devenv.local.yaml` itself is git-ignored and cannot be committed by accident.

The rewrite is genuinely unavoidable, and the reason is now traced to source rather than inferred.
Two mechanisms combine:

1. `original` is written **unstripped** (`src/libflake/lockfile.cc`), so any url change lands in it.
   No url spelling repoints the input without a change to `original`.
2. The staleness test is **full serialized-JSON equality of the whole lock graph**
   (`LockFile::operator==`, which compares `toJSON()`), and lock validation runs unconditionally
   before the backend is built.

devenv also offers no escape hatch: it has no `--frozen`, `--no-write-lock-file` or
`--no-update-lock-file`; `--offline` only changes substituters and applies after validation; and
devenv's `--override-input` rewrites the declared url rather than applying a sticky override.

### Why the trunk's own `nix-configs` lock node carries no rev — by design, not a gap

This came up as a suspected defect in the flake-update procedure, so it is recorded here. In the
trunk's `devenv.lock`, exactly **1 of 107** nodes has no `rev` and no `narHash`: `nix-configs`, the
self-input declared as `url: git+file:.`. It has never carried a rev in any revision of the file,
and in older revisions it was `{"path": ".", "type": "path"}`.

That is the same local-input strip described above — `file:` scheme, so every volatile attribute is
erased. Three further facts make it deliberate rather than accidental:

- The lock **parser** accepts an unlocked local node with no warning, and `LockFile::isUnlocked`
  never reports a local node as unlocked. So it cannot block a lock write.
- devenv depends on the behaviour. `devenv-nix-backend/bootstrap/resolve-lock.nix` explains that a
  local input with no pinned narHash must resolve to the live filesystem path, because a store copy
  would hide edits from the eval cache.
- devenv ships the same shape for itself: its own `devenv.yaml` declares `devenv: url: .?dir=src/modules`
  and its committed `devenv.lock` node has no `narHash` and no `rev`.

**Verdict: the node cannot be stabilized.** No devenv command, flag or url form writes a rev into
it, because the strip sits in the serializer downstream of every option. A local input is
intentionally not a pin — it is a live tree, re-read on every evaluation. So `nix run '.#update'`
plus `devenv update` leave the file correct, and no step is missing from the procedure. devenv's
own docs never mention this, which is why the shape reads as a defect.

## Exit criteria

All four are met. Solution: [jj-workspaces-parallel-agents.done.md](done.md).

1. [x] `docs/jujutsu-vcs.md` holds the full convention. `.agents/rules/jujutsu-vcs.md` holds the
       pointer and no longer names `../nix-configs-ws-<name>`. `CLAUDE.md` lists the doc.
2. [x] `nix run '.#jj-experiments-run' -- -k workspaces` passes every case — **17 passed** on
       2026-09-09, up from 16 with the new detection case.
3. [x] The bootstrap step, the activation prohibition, and the three hazards are written in prose an
       agent can follow with no further research.
4. [x] Checklist items 2 and 3 have a recorded decision.

## Out of scope

- Any change to the Agent/Workflow tool's `isolation` option. It creates a git worktree, which
  stays forbidden.
- A colocated jj workspace. Re-checked on jj **0.45.1**: `jj workspace add` still offers only
  `--name`, `-r/--revision`, `-m/--message` and `--sparse-patterns`. No colocate flag.
- An automatic workspace lifecycle wrapper. Establish the manual convention first.
- Any change to the trunk's `devenv.yaml` `inputs.nix-configs` URL.
- Multi-user or remote workspaces.
