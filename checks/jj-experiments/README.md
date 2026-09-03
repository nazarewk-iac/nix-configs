---
type: Reference
description: The isolated jj test harness for fork and branch use-case experiments — what it is, how to run it, and its mkrepo/Repo/JJConfig API.
timestamp: 2026-09-02T00:00:00+02:00
---

# jj-experiments — isolated jj test harness

This directory holds a pytest harness that runs jj and git against disposable,
fully isolated repos. It proves the golden-path recipes for the fork and branch
workflows on facts. Each `test_<group>.py` file pairs with a `<group>.md` file
that explains its use-cases.

See the design in
[../../docs/tasks/jj-fork-use-cases-refactor.design.md](../../docs/tasks/jj-fork-use-cases-refactor.design.md)
and the base patterns in [../../docs/jujutsu-vcs.md](../../docs/jujutsu-vcs.md).

## Complete `$HOME` isolation

Every test runs jj and git with a per-test temp tree. The fixtures set:

- `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME`
  → temp dirs.
- `JJ_CONFIG` → a temp file that holds the harness user name and email.
- `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null` → the real
  `~/.gitconfig` and `/etc/gitconfig` are ignored.
- `JJ_EDITOR`, `EDITOR`, `VISUAL`, `GIT_EDITOR` → `true`, so no editor opens.

`JJ_CONFIG` fully overrides the XDG search for the user config. jj keeps its
operation log and working state in each repo's `.jj/`, not under `$HOME`. So
nothing reads or writes the developer's real config, and every write stays in
the temp tree. The temp tree is removed on test teardown.

## Run modes

All modes run the same test files.

- **Flake check (headless, in the Nix sandbox):**
  ```bash
  nix build .#checks.<system>.jj-experiments-pytest
  ```
  The derivation renders the real fork slot config to a TOML file and exports
  its path as `JJ_FORK_CONFIG_TOML`.
- **Interactive (select a case):**
  ```bash
  cd checks/jj-experiments
  devenv shell
  pytest -k <case> -v
  ```
  The shell provides python, pytest, jujutsu, and git, and exports the same
  `JJ_FORK_CONFIG_TOML`.
- **Subset runner app (any pytest flags, hermetic, no `--impure`):**
  ```bash
  nix run .#jj-experiments-run -- -k <case> -x
  ```
  It forwards the args to a sandboxed `nom build` of `subset-runner.nix`. No args
  runs the whole suite. A re-run is a cache hit **only on an unchanged working
  tree** — `path:` re-hashes the whole tree, so any edit (even to an unrelated
  file) forces a rerun. On a cache hit it prints no test output; pass `--rebuild`
  to force a rerun.

A test that needs the real fork aliases calls `harness.slot_config()`. It skips
when `JJ_FORK_CONFIG_TOML` is absent (for example a bare `pytest` run with no
slot). The Phase 0 smoke tests need no slot and always run.

## The API

`conftest.py` provides two fixtures and three classes.

- `mkrepo(name=None, *, cfg=None) -> Repo` — make a disposable colocated jj repo.
  The harness remembers it and deletes it on teardown.
- `harness` — the owner of the isolated env. `harness.slot_config()` returns a
  `JJConfig` from the rendered fork slot (or skips). `harness.make_bare(label)`
  makes a bare git remote.

### `Repo`

- `.path` — the repo dir.
- `.jj(*args, check=True, input=None)` / `.jj_out(...)` — run jj in the repo.
- `.git(*args)` — run read-only or plumbing git in the repo.
- `.write(relpath, content)` — write a file.
- `.commit(message, files, ts=None)` — write files, describe `@`, start a fresh
  empty `@`; returns the described commit's change id.
- `.new(*parents, message=None, ts=None)` — make a commit on the parents; returns
  its change id.
- `.describe(message, rev="@", ts=None)` — set a commit message.
- `.change_id(rev="@")`, `.ids(revset)`, `.log_graph(revset)` — query the graph.
- `.register_remote(name, definition=None)` — add a git remote; `definition` is a
  bare-repo path or another `Repo`; `None` makes a fresh bare repo.
- `.bookmark_set(name, rev)`, `.push(remote, bookmark)`,
  `.push_to(remote, local_bm, remote_bm)`, `.fetch(*remotes)`.
- `.apply_config()` — install the base file (to `jj config path --<base_scope>`)
  and every persistent (file-layer) entry. `mkrepo` calls it; call it again after
  you swap `repo.cfg`.
- `.define_config(scope, "dotted.key", value)` / `.define_alias(name, argv,
  scope="repo")` — set one entry now at a chosen scope.

### `JJConfig` and the four config scopes

jj has four config targets, each a `scope`:

| scope | where | precedence | notes |
|---|---|---|---|
| `flag` | `--config NAME=VALUE` per call | highest | ephemeral; **cannot** hold command aliases |
| `repo` | `jj config path --repo` | over user | the default for the slot base and for `alias` |
| `workspace` | `jj config path --workspace` | over repo? per jj | per-workspace file |
| `user` | `jj config path --user` (`JJ_CONFIG`) | lowest file layer | shared user config |

jj does **not** read `.jj/repo/config.toml`; that path is a jj-made symlink to
the canonical `jj config path --repo`. The harness writes to the canonical path.

Shortcuts take a `scope` (default `flag`, except `alias` which defaults `repo`):

- `JJConfig.from_slot(path, scope="repo")` / `JJConfig.without_slot()`.
- `.revset_alias(name, expr, scope="flag", deferred=False)`.
- `.alias(name, argv_list, scope="repo")` — command aliases; `scope="flag"` is
  rejected (jj refuses them from `--config`).
- `.set("dotted.key", value, scope="flag", deferred=False)`.
- `.merge({...}, scope="flag", deferred=False)`.
- `.activate_deferred()` — apply the deferred flag overlays. Use this for a
  `trunk()`/`immutable_heads()` alias that names a ref created later, so it does
  not break jj commands before the ref exists.

`flag`-scope entries apply as `--config` args on every jj call (so they win).
File-layer entries apply through `Repo.apply_config` / `define_config`.

### Usage snippet

```python
def test_example(mkrepo):
    repo = mkrepo()
    base = repo.commit("feat: base", {"a.txt": "1\n"})
    repo.register_remote("origin")
    repo.bookmark_set("main", base)
    repo.push("origin", "main")
    assert repo.ids('remote_bookmarks(remote="origin")')
```

## Deterministic timestamps

jj `latest()` (and the `*-tip` aliases) pick by commit time. Each commit gets an
explicit, increasing time through `--config debug.commit-timestamp`. So the tip
aliases resolve the same way on every run, with no sleeps.

## Layout convention

- `conftest.py` — the isolation base, `mkrepo`, `Repo`, `JJConfig`.
- `test_<group>.py` — one file per use-case family; the executable examples.
- `<group>.md` — the detailed prose for that family, linking to the test
  functions that prove each caveat.
- `test_smoke.py` is the harness self-test, not a use-case family, so it is the
  one `test_*.py` file with no paired `.md`.

## Test a case on-demand, or embed it

To check a jj recipe on-demand — or embed it permanently — add a small test
function to a `test_<group>.py` (build state with `mkrepo`/`Repo`/`JJConfig`),
then run it hermetically:

```bash
nix run .#jj-experiments-run -- -k <name>     # sandboxed; or `pytest -k <name>` in the devenv shell
```

Delete a throwaway function when done; keep it to record the case permanently.

**A throwaway check is loose — it may skip these conventions. Anything you commit MUST follow
them:** build state through `mkrepo`/`Repo`/`JJConfig` (never touch the real repo), stamp
deterministic commit times, pair a `test_<group>.py` with a `test_<group>.md` (see
[Layout convention](#layout-convention)), write prose in Simple Technical English, and use
placeholder patterns only — never a real sensitive term. The design and philosophy behind these
conventions are in the
[design doc](../../docs/tasks/jj-fork-use-cases-refactor.design.md).
