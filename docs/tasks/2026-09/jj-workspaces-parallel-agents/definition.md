---
type: Task
description: Adopt jj workspaces as the sanctioned isolation mechanism for parallel sub-agent work, with a sibling naming convention, a mandatory bootstrap step, and a ban on system activation from a workspace.
status: open
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

`jj workspace update-stale` recovers a stale workspace. Exactly one condition produces one: a
repo-wide op-log rewind (`jj op restore`) run from another workspace. An ordinary rewrite of the
workspace's `@` does not — jj 0.44 recovers on its own.

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
aliases and the push checks **from the trunk as well**. The failure is silent.

`jj config path --workspace` is per workspace, so it is unaffected.

Do **not** copy anything else. `.devenv/`, `.direnv/`, `.pre-commit-config.yaml`,
`.claude/settings.json`, `.agents/skills/`, and every `/nix/store` symlink regenerate on the first
`devenv shell` in the workspace.

## Hazard: a workspace has no `.git`

A workspace directory holds `.jj` and no `.git` at all. Two consequences:

1. `devenv.yaml` sets `inputs.nix-configs.url = git+file:.`, and `flake.nix` sets
   `nix-configs = self`. Both resolve through a `git+file://` fetcher, which needs a `.git`. Neither
   works from a workspace.
2. The git-hooks install task has no repo to install into.

`path:.` is **not** a substitute. It needs no `.git`, but it copies git-ignored files into the
store, and `.devenv/` alone is hundreds of megabytes.

Chosen mitigation: an absolute, pinned reference to the trunk checkout,
`git+file:///<abs-path-to-trunk>?rev=<commit-id>`. The pin has a second benefit: it removes the
`prek` / `git write-tree` re-snapshot race that has truncated files in the trunk.

## devenv independence

devenv state is per-directory, so a workspace and the trunk do not collide:

| devenv value | Definition | Independent? |
|---|---|---|
| `DEVENV_ROOT` | the shell's directory | yes |
| `DEVENV_DOTFILE` | `DEVENV_ROOT + "/.devenv"` | yes |
| `DEVENV_STATE` | `DEVENV_DOTFILE + "/state"` | yes |
| `devenv.runtime` | `<XDG_RUNTIME_DIR or /tmp>/devenv-<sha256(dotfile)[0:7]>` | yes — the hash is over the dotfile path |
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

- [ ] Add a `jj workspaces` section to `docs/jujutsu-vcs.md`: the naming convention, the creation
      command, the verify step, the bootstrap step, the cleanup step, and the hazards above.
- [x] Replace the `../nix-configs-ws-<name>` guidance in `.agents/rules/jujutsu-vcs.md` with a
      pointer to that section, plus the naming pattern and the activation prohibition in short form.
      Done 2026-09-09: the rule file, `docs/jujutsu-vcs.md` and `docs/vcs-workspaces.md` all name
      `../.nix-configs--<slug>` and the mandatory `--name <slug>`. The activation prohibition is
      still only in this task file — item 1's first box owns that move.
- [ ] Add the doc row to the `docs/` table in `CLAUDE.md`.

### 2. Guard the shared jj repo config

- [ ] Decide whether `modules/slots/jj/default.nix` should refuse to write the shared repo config
      when the current workspace is not `default`, or whether the mandatory bootstrap step is
      enough. Record the decision here.

### 3. Decide the `git+file:` mitigation

- [ ] Record how a workspace overrides `inputs.nix-configs`. Candidates: a `devenv.local.yaml` with
      the absolute pinned URL, or a documented `--override-input` on the command line. Do not change
      the trunk's `devenv.yaml`.

## Exit criteria

1. `docs/jujutsu-vcs.md` holds the full convention. `.agents/rules/jujutsu-vcs.md` holds the
   pointer and no longer names `../nix-configs-ws-<name>`. `CLAUDE.md` lists the doc.
2. `nix run '.#jj-experiments-run' -- -k workspaces` passes every case.
3. The bootstrap step, the activation prohibition, and the three hazards are written in prose an
   agent can follow with no further research.
4. Checklist items 2 and 3 have a recorded decision.

## Out of scope

- Any change to the Agent/Workflow tool's `isolation` option. It creates a git worktree, which
  stays forbidden.
- A colocated jj workspace. jj 0.44.0 has no `jj workspace add --colocate` flag.
- An automatic workspace lifecycle wrapper. Establish the manual convention first.
- Any change to the trunk's `devenv.yaml` `inputs.nix-configs` URL.
- Multi-user or remote workspaces.
