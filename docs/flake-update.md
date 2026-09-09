---
type: Playbook
description: Procedure for periodically updating flake inputs and handling post-update fixes.
timestamp: 2026-07-10T12:19:48+02:00
---

# Flake Update Procedure

> **Agent summary:** [.agents/rules/flake-update.md](../.agents/rules/flake-update.md)

Run periodically to pull in new upstream nixpkgs, home-manager, and other inputs.

For fork-specific workflow (merging a private fork's flake.lock), see
[flake-update.fork.md](flake-update.fork.md).

For jj patterns referenced here, see [jujutsu-vcs.md](jujutsu-vcs.md).

---

## Which procedure applies

> **This procedure applies when `kdn.jj.fork.enable = false`.** In a repo that maintains a private
> fork remote, [flake-update.fork.md](flake-update.fork.md) **overrides every step below** — the
> commit structure, the bookmark handling and the testing gates all differ.
>
> In a fork repo, `jj sync-remotes` moves every bookmark from the topology. **Never run
> `jj bookmark set`** there. The `jj bookmark set` commands below are correct only in a non-fork
> repo.

---

## Commit structure

The update produces a chain on top of the current `upstream` bookmark:

```
upstream ──► chore(flake): update
         ──► fix(...): post-update fixes   ◄── upstream bookmark (advanced)
```

`@` (empty working copy) should always sit on top of `upstream`.

---

## Quick summary

```bash
jj git fetch --all-remotes   # ALWAYS first — the update itself never fetches
# @ is the empty working copy on top of upstream
nix run '.#update'
devenv update    # updates devenv.lock (separate resolver from flake.lock)
# if a patch fails: remove it from .flake.patches/config.toml + delete .patch file, then:
#   nix run '.#update' -- g:patches
jj describe -m 'chore(flake): update'
jj bookmark set upstream -r @-
# test (./nixos-rebuild.sh build / nix run '.#darwin-rebuild' -- build), then fix failures:
# split fixes into named commits:
#   jj split -m 'fix(...): description' -- <changed-files>
#   jj bookmark set upstream -r 'upstream-tip'
```

---

## Step-by-step

### 0. Fetch, then reconcile

```bash
jj git fetch --all-remotes
jj log -r 'main@<public-remote>..@'   # your local work, not on the remote yet
jj log -r '@..main@<public-remote>'   # new remote commits, not in your tree yet
```

`nix run '.#update'` runs `nix flake update` and the patch updater only. It **never** fetches. So
without this step every later revision reads a stale remote-tracking ref.

When the second command prints commits, the public tip moved. Rebase your local chain onto the new
tip **before** you start the update, so the update lands on current history:

```bash
jj rebase -s 'roots(main@<public-remote>..@)' -d 'main@<public-remote>'
```

When both commands print nothing, there is nothing to reconcile. Go on.

### 1. Run the update

With `@` as the empty working copy on top of `upstream`, run:

```bash
nix run '.#update'
devenv update
```

`nix run '.#update'` updates all flake inputs and fetches/applies patches from `.flake.patches/`.
`devenv update` updates `devenv.lock`, which has a separate resolver. Without a fork, both lock
files go into the same described commit — no strip step is needed.

If a patch fails to apply, **find the cause first**. The action differs per cause, so do not
default to deleting the patch. The full decision procedure lives in
[flake-patches.md](flake-patches.md) and in the `flake-patches` skill.

| Cause | Detection | Action |
|---|---|---|
| the patch landed upstream | `gh api "repos/NixOS/nixpkgs/compare/nixos-unstable...<commit>" --jq '.status'` returns `behind` or `identical` | remove the entry from `.flake.patches/config.toml`, delete the `.patch` file |
| the patch has not landed yet, and the context moved | the same call returns `ahead`, and the hunk offsets fail | re-fetch the patch from the PR, keep the entry |
| the upstream PR was closed or rewritten | the patch URL 404s, or the diff changed shape | decide whether the change is still wanted; re-derive or drop it |

Then re-run patches only (the inputs are already updated):

```bash
nix run '.#update' -- g:patches
```

### 2. Describe and advance upstream

```bash
jj describe -m 'chore(flake): update'
jj bookmark set upstream -r @-
```

`@-` is the parent of the current empty working copy — the commit that holds the update
changes. You can also use the explicit change ID or `upstream-tip` as the
revision. A fresh empty `@` sits on top automatically.

### 3. Test (see Testing section below)

### 4. Post-update fixes

If the build fails, make fixes in `@`. Use `jj split` to carve them into a named commit.
It opens an editor interactively by default — great in a terminal. Pass `-m` and `--` to skip
the editor:

```bash
# interactive (pick hunks/files in terminal):
jj split

# or non-interactively by file:
jj split -m 'fix(...): description' -- <changed-files>

jj bookmark set upstream -r 'upstream-tip'
```

Repeat until the build passes.

---

## Testing

### macOS (Darwin) — build

Use the pre-update revision to run `darwin-rebuild` without rebuilding it against the new
inputs (faster, avoids unnecessary recompilation of the tool itself):

```bash
PRE_UPDATE_REV=$(jj log -r 'main@<public-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#darwin-rebuild" -- build
```

A non-fork repo has no fork remote, so the anchor is `main@<public-remote>`. In a fork repo the
anchor is `upstream@<fork-remote>` — see [flake-update.fork.md](flake-update.fork.md).

Or use the current working tree (rebuilds the app against new inputs):

```bash
nix run '.#darwin-rebuild' -- build
```

Run in the background and tail the log:

```bash
nix run '.#darwin-rebuild' -- build > /tmp/darwin-build.log 2>&1 &
tail -f /tmp/darwin-build.log
```

Once the build succeeds, activate (requires sudo — run this yourself):

```bash
nix run '.#darwin-rebuild' -- switch
```

### NixOS — local host

```bash
./nixos-rebuild.sh build
./nixos-rebuild.sh switch   # requires sudo
```

### NixOS — remote host

```bash
./nixos-rebuild.sh build  remote=<hostname>
./nixos-rebuild.sh switch remote=<hostname>   # requires sudo on remote
```

`<hostname>` is the short name (e.g. `oams`, `brys`, `etra`). The script auto-discovers the
full address via the `check_domains` list. Override the config name or SSH address with:

```bash
./nixos-rebuild.sh build remote=etra=kdn@etra.netbird.cloud
```

Tested NixOS hosts: `brys`, `etra`, `oams`. Darwin host: `anji`.
