---
type: Task
description: Solution for the fork revset-alias pytest suite — built inside the jj-experiments harness.
authored_by: agent
timestamp: 2026-09-02T00:00:00+02:00
---

# Solution — pytest suite for jj fork revset aliases

> Completed as part of [jj-fork-use-cases-refactor](jj-fork-use-cases-refactor.md). That task
> builds the shared `checks/jj-experiments/` harness; this suite is the first test group in it,
> so the two tasks were finished together.

## Root cause analysis

The fork revset aliases (`tree-merge`, `upstream-incoming`, `to-rebase`, `upstream-safe`,
`fork-direct`, `fork-leaked`, `pushed*`, `merge-frozen`, `upstream-local`, `*-tip`, `*-chain`)
were pure config in `modules/slots/jj/fork/default.nix` with no automated proof. Their behavior
had subtle points (the `~fork` vs `~fork-direct` trap, timestamp-based `latest()`, the virtual
root commit in `pushed`) that needed a reproducible test.

## Solution

Built the suite inside the shared harness at `checks/jj-experiments/`:

- `conftest.py` — complete `$HOME` isolation (HOME, XDG_*, JJ_CONFIG, git global and system
  config to a temp tree), `mkrepo`/`Repo`/`JJConfig`, deterministic commit times, and bare-remote
  push/fetch. Command aliases go through the repo config file (jj refuses them from `--config`);
  revset aliases and scalars use `--config` overlays.
- `topologies.py` — `build_reference` builds the known graph (A, P1, P2, U1, U2, F1, M, L1, L2,
  L3, @) with real bare `upstream` and `fork` remotes, then installs the real fork aliases.
- `test_revsets.py` — asserts every alias resolves to the expected set, and proves the `~fork`
  trap (`to-rebase & ~fork == {}` while `to-rebase & ~fork-direct == {L1, L3}`).
- `revsets.md` — the paired prose: topology, alias→set→test table, and the caveats.

The real fork config is rendered from the slot with `lib.kdn.mkSlots` → `.config.kdn.jj.config`
→ `pkgs.formats.toml`, and passed to the tests via `JJ_FORK_CONFIG_TOML`.

## Verification steps

- `pytest checks/jj-experiments/` with `JJ_FORK_CONFIG_TOML` set → 20 passed (7 smoke + 13
  revset).
- `nix build path:.#checks.<system>.jj-experiments-pytest -L` → 20 passed inside the sandbox with
  the real rendered TOML (Python 3.14).
- `devenv shell` in `checks/jj-experiments/` exports a valid `JJ_FORK_CONFIG_TOML` and provides
  jj/pytest/git, so selective `pytest -k <case>` runs interactively.

## Follow-up notes

- Two findings resolved: `pushed*` reaches jj's virtual root (`root()`), so assertions exclude it;
  `latest()` is timestamp-based, so the harness stamps deterministic increasing commit times.
- The suite lives in the harness built by `docs/tasks/jj-fork-use-cases-refactor.md`. The
  remaining use-case golden paths continue under that task.
