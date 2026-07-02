# Flake Update Procedure

> **Agent summary:** [.agents/rules/flake-update.md](../.agents/rules/flake-update.md)

Run periodically to pull in new upstream nixpkgs, home-manager, and other inputs.

For fork-specific workflow (merging a private fork's flake.lock), see
[flake-update-fork.md](flake-update-fork.md).

For jj patterns referenced here, see [jj-workflows.md](jj-workflows.md).

---

## Commit structure

The update produces a **kdn-side chain** on top of the current `upstream` bookmark:

```
upstream ──► chore(flake): update
         ──► fix(...): post-update fixes   ◄── upstream bookmark (advanced)
```

`@` (empty working copy) should always sit on top of `upstream`.

---

## Quick summary

```bash
# @ is the empty working copy on top of upstream
nix run '.#update'
# if a patch fails: remove it from .flake.patches/config.toml + delete .patch file, then:
#   nix run '.#update' -- g:patches
jj describe -m 'chore(flake): update'
jj bookmark set upstream -r @-
# test (./nixos-rebuild.sh build / nix run '.#darwin-rebuild' -- build), then fix failures:
# split fixes into named commits:
#   jj split -m 'fix(...): description' -- <changed-files>
#   jj bookmark set upstream -r 'latest(upstream-candidates)'
```

---

## Step-by-step

### 1. Run the update

With `@` as the empty working copy on top of `upstream`, run:

```bash
nix run '.#update'
```

This updates all flake inputs and fetches/applies patches from `.flake.patches/`.

If a patch fails to apply, check whether it was already merged into the upstream repo:
- If merged: remove the entry from `.flake.patches/config.toml` and delete the `.patch` file.
- Then re-run patches only (inputs already updated):
  ```bash
  nix run '.#update' -- g:patches
  ```

### 2. Describe and advance upstream

```bash
jj describe -m 'chore(flake): update'
jj bookmark set upstream -r @-
```

`@-` is the parent of the current empty working copy — the commit that holds the update
changes. You can also use the explicit change ID or `latest(upstream-candidates)` as the
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

jj bookmark set upstream -r 'latest(upstream-candidates)'
```

Repeat until the build passes.

---

## Testing

### macOS (Darwin) — build

Use the pre-update revision to run `darwin-rebuild` without rebuilding it against the new
inputs (faster, avoids unnecessary recompilation of the tool itself):

```bash
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#darwin-rebuild" -- build
```

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
