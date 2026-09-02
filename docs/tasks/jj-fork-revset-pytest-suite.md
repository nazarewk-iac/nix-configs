---
type: Task
description: Build a pytest suite that spins up a self-contained devenv plus three colocated jj repos (local, upstream, fork) to verify the fork revset aliases behave as documented.
status: done
authored_by: agent
timestamp: 2026-08-03T15:15:00+02:00
---

# pytest suite for jj fork revset aliases

Verify the fork revset aliases (`tree-merge`, `upstream-incoming`, `upstream-incoming-tip`,
`to-rebase`, `upstream-safe`, `pushed`, `pushed-fork`, `pushed-upstream`, plus the earlier
`fork` / `fork-direct` / `upstream-chain` / `fork-chain` / `*-tip`) resolve to the correct
change sets against a known, reproducible topology.

The aliases live in `modules/slots/jj/fork/default.nix`. They are pure config, so a test can
render them and evaluate a revset without a real fork remote in the way.

## Goal

A pytest suite that, per test function, builds an isolated world:

1. A temporary directory with its own `devenv` config. Symlink the repo root into it and
   reference this repo through `git+file:` (so the test uses the real slot definitions, not a
   copy).
2. Three temporary **colocated** jj repositories, one set per test function (fresh state per
   test, no cross-test bleed):
   - `local` — the working checkout.
   - `upstream` — stands in for the public upstream remote.
   - `fork` — stands in for the private fork remote.
3. Wire `local` to fetch from `upstream` and `fork`, build a small known history (an upstream
   chain, a fork chain, a merge, and a few local changes above the merge), then assert each
   alias returns the expected change ids.

Cover at least:
- `upstream-incoming` = fetched-but-not-merged upstream commits; `upstream-incoming-tip` = its
  latest.
- `to-rebase` = local described work above `tree-merge`.
- `upstream-safe` = `to-rebase & ~fork-direct` (content-clean subset).
- `pushed` / `pushed-fork` / `pushed-upstream` reachability, and how they relate to
  `immutable()`.
- The known subtlety: `~fork` drops safe local changes (the `fork` alias tags every descendant
  of fork main), so `upstream-safe` must use `~fork-direct`.

## Potential ideas — verify before you build (may not make sense)

Treat the two items below as unverified hypotheses. Check each is real and worth it before you
depend on it. Drop or change it if it does not hold.

- **Render the jj config to an internal option — RESOLVED: no new option is needed.** `mkSlots`
  (`lib/slots/default.nix`) `renderTarget` already imports a read-only `slots` option that
  carries the full evaluated parent slot config into every target. So the test reads the exact
  rendered alias strings with `devenv eval`:
  ```bash
  devenv eval 'slots.kdn.jj.config'        # whole rendered jj config, all aliases
  devenv eval 'slots.kdn.jj.fork.enable'   # any scalar sub-path works directly
  ```
  Note: the `devenv eval` CLI takes an attr-path, not an expression. It chokes on a quoted
  hyphenated sub-path (`slots.kdn.jj.config."revset-aliases"."to-rebase"` fails to parse), so
  read the parent attr `slots.kdn.jj.config` and pick the key in the test instead. The generated
  TOML does not need parsing.
- **Self-reference into the repo from the temporary devenv.** Idea: the temporary devenv points
  `inputs.nix-configs` (or equivalent) at this repo so the test runs the real slot code. Two
  fetcher choices, with different semantics (see the "Colocation hazard" notes in
  [docs/jujutsu-vcs.md](../jujutsu-vcs.md) and the self-reference notes in
  [.agents/rules/nix-conventions.md](../../.agents/rules/nix-conventions.md)):
  - `git+file:` reads git's index. It shows committed changes and dirty edits to tracked files,
    but NOT a brand-new untracked file until `git add`.
  - `path:` copies the working directory (filtered by `.gitignore`) and sees new files at once.
  The suite very likely needs `path:` — an isolated flake test would otherwise resolve this repo
  through `/nix/store` and miss uncommitted test fixtures. Verify: does the chosen fetcher read a
  symlinked, possibly-dirty tree the way the test needs?

## Notes

- Colocated jj repos need care: never run concurrent writers against one `.jj` store. One repo
  set per test function keeps them independent.
- The suite validates config semantics (revset results), not a live push to a real remote.
- Relates to the open "Improve the fork validation logic" item in `TASKS.md` — the same
  `~pushed` / `fork-direct` predicates drive the pre-push and pre-commit checks.
