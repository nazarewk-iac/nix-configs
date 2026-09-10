---
type: Task
description: Solution for jj-fork-use-cases-refactor — the isolated pytest harness, the verified golden-path matrix, and the docs/skill rewrite.
authored_by: agent
timestamp: 2026-09-03T00:00:00+02:00
---

# Solution — jj fork change-placement: harness, matrix, docs

## Root cause analysis

The skill and the fork docs gave inconsistent guidance on `jj split` placement in the fork
topology. `-A`/`-B` were presented as the default, but their behavior depends on whether the
affected merge is mutable or frozen (pushed) — a distinction the docs did not make. There was no
automated way to prove any recipe, so guidance drifted and contradicted itself. The task needed
one coherent, verified reference for every change-placement and day-to-day jj case.

## Solution

Built an isolated pytest harness and verified a golden path for each use-case, then rewrote the
docs and skill from the verified results.

- **Harness — `checks/jj-experiments/`.** Complete `$HOME` isolation (`HOME`, `XDG_*`,
  `JJ_CONFIG`, git global/system config → a per-test temp tree). `conftest.py` gives `mkrepo` →
  `Repo` (`.jj`, `.cfg`, `commit_id`, `register_remote`, deterministic commit times) and
  `JJConfig` (four scopes: flag/user/repo/workspace). `topologies.py` builds known graphs with
  real bare `upstream` and `fork` remotes and the real slot-rendered fork revset aliases. Three
  run modes share one test suite: the flake check
  `nix build .#checks.<system>.jj-experiments-pytest`, an interactive `devenv shell`, and a
  hermetic subset runner `nix run .#jj-experiments-run -- <pytest-flags>`.
- **83 tests across 14 use-case groups** at this task's completion (plus a `test_smoke`
  self-test group); later extended to 92 tests / 15 groups by the `test_push` group.
  Each `test_<group>.py` is paired with a `test_<group>.md`:
  revsets, placement, pull-upstream (frozen/mutable/conflict), fork hazards & forbidden ops,
  de-leak & X→Y, squash-vs-`jj absorb`, restructure, amend, discard/recover,
  bookmarks/sync/untrack, inspect/read, conflicts, long-lived-branch mode,
  advanced/agent-centric revset idioms.
- **`jj fork-audit` tool** (`modules/slots/jj/fork/fork-audit.sh` + slot wiring): lists
  fork-sensitive content at line level, colored and TTY-gated, reusing the slot's denied patterns.
- **Docs rewrite.** `docs/jujutsu-vcs.md` is the primary home (day-to-day golden paths + a
  golden-path index; reframed `rebase`/`edit` as normal tools on mutable commits).
  `docs/jujutsu-vcs.fork.md` is a thin fork-only reference (topology, alias table, fork golden
  paths), each recipe linking to its proof test. `.agents/skills/jujutsu-vcs/SKILL.md` shortened
  (149 → 86 lines) to critical rules + a golden-path table with links. `docs/flake-update.fork.md`
  reconciled.
- **Decisions recorded:** fork-content routing by kind (leaf tweak above the merge; durable
  fork-base into a new merge). The verified unified placement recipe (`jj new --no-edit -B @` then
  `jj split -A upstream-tip -B fork-tip`) works on both a frozen and a mutable tree; a single
  `jj split -A upstream-tip -B fork-tip` suffices when a mutable merge already exists.
- **Also fixed:** `.gitignore` did not track `*.py` (the harness would not have committed) — added
  `!*.py`. Scrubbed sensitive terms from the task doc.

## Verification steps

- `export JJ_FORK_CONFIG_TOML=<rendered slot config>; pytest checks/jj-experiments/` → 83 passed.
- `nix build path:.#checks.<system>.jj-experiments-pytest -L` → 83 passed in the sandbox with the
  real slot-rendered aliases.
- `nix build --file checks/jj-experiments/subset-runner.nix --argstr extraArgsJSON '[]' -L` → 83
  passed; a `-k <expr>` subset builds and runs only the selected tests.
- `devenv shell` in `checks/jj-experiments/` runs selective `pytest -k <case>`.
- `jj log -r 'fork-leaked'` empty throughout; sensitive-term scans of all committed files clean.

## Follow-up notes

- Workspace / parallel-work golden paths are out of scope (kept as hazard guidance only).
- The long-lived-branch generalization is built out and proven (`test_branch.py`,
  `topologies.build_branch_tree`): plain split, integrate-trunk by rebase or by merge, an
  immutable pushed trunk, and an upstream-only fetch+rebase. It is the fork model minus the fork
  remote and the content split. The harness extends per-group easily.
- The `.design.md` is retained as the design and philosophy reference (linked from the harness
  README, the skill, and the jj-expert agent), not deleted on completion.
- `jj absorb` is verified (routes hunks to the last toucher, skips immutable ancestors, leaves
  ambiguous hunks) and is a safe low-cognitive-load substitute for a manual squash.
