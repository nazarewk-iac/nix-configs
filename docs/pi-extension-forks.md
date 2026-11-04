---
type: Guide
description: How this repository forks a Pi extension into nazarewk-iac, patches it, vendors it at a pinned revision, and upgrades it.
timestamp: 2026-11-03T13:40:00+01:00
---

# Forking a Pi extension

Use this when a vendored Pi extension must change and upstream does not have the change.

## Fork and branch — jj bookmarks, joined into `main`

The fork is a normal git repo that we drive with **jujutsu** (`jj git init --colocate` converts an
existing clone, so the git remote and the jj view share one object store). Bookmarks are branches;
there is no branch checkout to get wrong.

1. Fork into the `nazarewk-iac` organisation and clone into a scratch dir, then add upstream:
   ```sh
   gh repo fork <owner>/<repo> --org nazarewk-iac --clone=false
   gh repo clone nazarewk-iac/<repo> /tmp/<repo>-fork
   jj git init --colocate                       # one store, git remotes still work
   jj git remote add upstream https://github.com/<owner>/<repo>.git
   jj git fetch --remote upstream
   ```
2. **One bookmark per feature**, cut from the commit we currently vendor:
   ```sh
   jj new <vendored-rev> -m "feat: <feature>"
   # ... edits ...
   jj bookmark create <feature>                 # e.g. runs-peek, session-stats
   ```
3. **Join the features in one change, bookmarked `main`.** A change with two parents is a merge;
   nothing is rewritten:
   ```sh
   jj new <feature-a> <feature-b> -m "merge <feature-a> and <feature-b>"
   jj bookmark set main -r @
   jj new                                       # keep @ empty; @- is now the join
   ```
   So the vendoring point is always `@-` while you work, and it is the `main` bookmark. A feature
   is added later by `jj new main <new-feature>` + `jj bookmark set main -r @`.
4. Push the bookmarks (never a branch checkout, never a force-push of unrelated refs):
   ```sh
   jj git push --bookmark main --bookmark <feature>
   ```
5. Vendor the **`main` commit**: `rev` is `main`'s commit id, so "the vendored line" and "the fork's
   main" are the same thing and no branch name has to be remembered.

### Upstream moves

`upstream/main` is the reference, not the fork's `main`. On an upstream update:

```sh
jj git fetch --remote upstream
jj rebase -s <feature-a> -d upstream/main      # and each other feature bookmark
jj new <feature-a> <feature-b> -m "merge ..."  # re-join
jj bookmark set main -r @
jj new
```

Consequence, recorded because it reverses the older rule: the fork's `main` is **no longer identical
to upstream**. It is the joined integration line, and `upstream/main` holds the pristine copy. That
is the price of a single, always-vendorable bookmark; the alternative (topic branches we vendor
directly) needs a branch name in every bump and loses the merge topology.

## Patch

- One commit per change, with a message that says what and why.
- Keep the diff small and upstreamable. Add a config or an environment switch instead of a
  hard-coded behaviour when the behaviour should be optional.
- Signing off is not needed: this repository commits with `jj` and so should the fork (see the
  general guide); if you must commit with plain git and `commit.gpgsign` fails, pass
  `-c commit.gpgsign=false` for that one commit.
- Run the fork's own checks before you push:
  ```sh
  npm ci
  npx tsc --noEmit
  npm test
  ```

## Vendor it

In `packages/pi-coding-agent-extensions/default.nix`:

```nix
rev = "<full 40-char commit on the fork branch>";
version = "<upstream-version>+nazarewk.<N>";
src = pkgs.fetchzip {
  url = "https://github.com/nazarewk-iac/<repo>/archive/${rev}.tar.gz";
  hash = "<sha256>";
  stripRoot = true;
};
```

- Bump `rev`, `hash` and the `+nazarewk.N` suffix together. A changed tree changes the hash.
- Build the extension locally. The remote builder may reject an unsigned fixed-output
  derivation; build with `--option builders ""` then:
  ```sh
  nix build --impure --no-link --print-out-paths --option builders "" --expr \
    'let pkgs = import (builtins.getFlake "path:.").inputs.nixpkgs { system = "x86_64-linux"; };
     in (pkgs.callPackage ./packages/pi-coding-agent-extensions { }).<attr>'
  ```
- Load it in Pi and confirm there is no load error. A malformed piece of frontmatter or a bad
  import fails the whole extension at startup:
  ```sh
  devenv shell -- pi --no-session --provider brys --model tiny-dumb-fast --print --no-tools 'Reply with exactly OK'
  ```
  A `Failed to load extension` line means the build is not usable.

## Upgrade

When upstream moves:

1. `git fetch upstream`, rebase `nazarewk-iac/<topic>` onto the new upstream tag or commit.
2. Keep `main` equal to upstream (`git checkout main && git merge --ff-only upstream/main`).
3. Re-run the fork checks, push the branch, then bump `rev`/`hash` in `default.nix`.

If the patch lands upstream, drop the fork: point `default.nix` at upstream again and delete the
branch.

## Sync hazards

- `checks/pi-harness/extensions/` holds **copies** of some extension sources. Sync a changed
  extension there (the tree ignores it by default; only `packages/` opts into git).
- `~/.pi/agent/agents/` is a one-time **copy**, not a symlink. Edit the repo copy and copy it over,
  or the installed agent drifts from the repo.
- A colon inside an unquoted frontmatter value is invalid YAML and breaks the load. Quote the
  value.

## Forks today

| upstream                      | branch                                                         | patch                                                                                                                              |
| ----------------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `michaelmjhhhh/pi-atelier`    | `nazarewk-iac/jj-and-stats`                                    | jj over git, change id and bookmarks, STATS panel                                                                                  |
| `saifymatteo/pi-orchestrator` | `main` (integration) + `session-stats`, `runs-peek` (features) | config-driven minimal child context, session stats in the fleet panel, `/orchestrator-runs` + `ctrl+alt+r` to open a run in a pane |
