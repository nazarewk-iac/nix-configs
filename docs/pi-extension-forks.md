---
type: Guide
description: How this repository forks a Pi extension into nazarewk-iac, patches it, vendors it at a pinned revision, and upgrades it.
timestamp: 2026-11-03T13:40:00+01:00
---

# Forking a Pi extension

Use this when a vendored Pi extension must change and upstream does not have the change.

## Fork and branch

1. Fork into the `nazarewk-iac` organisation: `gh repo fork <owner>/<repo> --org nazarewk-iac --clone=false`.
2. Clone the fork, then add upstream and fetch it:
   ```sh
   gh repo clone nazarewk-iac/<repo> /tmp/<repo>-fork
   git -C /tmp/<repo>-fork remote add upstream https://github.com/<owner>/<repo>.git
   git -C /tmp/<repo>-fork fetch upstream --tags
   ```
3. Branch from the **exact revision we vendor**, not from `main`, so the patch applies to what is
   built:
   ```sh
   git -C /tmp/<repo>-fork checkout -b nazarewk-iac/<topic> <vendored-rev>
   ```

Keep the fork's `main` **identical to upstream**. Do not commit to `main`. This makes a later
rebase and a re-vendor trivial.

### One branch per feature, merged into the vendoring branch

Do not stack unrelated work on the vendored branch. Branch per feature from the vendored rev, and
merge the feature branch into the branch the pin names:

```sh
git -C /tmp/<repo>-fork checkout -b nazarewk-iac/<feature> <vendored-rev>
# ... commits, tests ...
git -C /tmp/<repo>-fork checkout nazarewk-iac/<vendoring-branch>
git -C /tmp/<repo>-fork merge --no-ff -m "merge nazarewk-iac/<feature>: <what>" nazarewk-iac/<feature>
```

The pin then points at the **merge commit**. Two reasons: a feature can be dropped or reverted by
one merge, and `git log --first-parent` still reads as the vendoring line. `pi-orchestrator` works
this way — `nazarewk-iac/child-context` is the vendoring branch, and `runs-peek`, `session-stats`
are features merged into it.

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

| upstream                      | branch                                                                                                       | patch                                                                                                                              |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `michaelmjhhhh/pi-atelier`    | `nazarewk-iac/jj-and-stats`                                                                                  | jj over git, change id and bookmarks, STATS panel                                                                                  |
| `saifymatteo/pi-orchestrator` | `nazarewk-iac/child-context` (vendoring) + `nazarewk-iac/session-stats`, `nazarewk-iac/runs-peek` (features) | config-driven minimal child context, session stats in the fleet panel, `/orchestrator-runs` + `ctrl+alt+r` to open a run in a pane |
