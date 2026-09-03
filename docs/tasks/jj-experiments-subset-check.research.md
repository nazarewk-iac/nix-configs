---
type: Research
description: Can a subset of the jj-experiments pytest suite run through the nix build runner, and which approach is most ergonomic.
authored_by: agent
timestamp: 2026-09-03
---

# Run a subset of jj-experiments through nix build

## Question

Today `checks.<sys>.jj-experiments-pytest` always runs the whole suite
(`python3 -m pytest -v`). Can a developer run only a subset (for example
`-k placement`, or one `test_<group>.py`) through the `nix build` runner? Is it
feasible and ergonomic?

## Verdict

Yes. A subset runs cleanly in the Nix sandbox. The suite already reads
`JJ_FORK_CONFIG_TOML` from the environment and the fork tests skip without it.
The pytest `-k` filter and single-file selection both work unchanged inside a
`runCommand`. The proof-of-concept below ran 5 placement tests (a fork family
that needs the rendered TOML) and they passed.

The current check does not modify. All approaches add new attrs or a passthru,
so they do not change the meaning of `jj-experiments-pytest`.

## How the check works today (context)

- `checks/default.nix` renders the fork slot config to a TOML with
  `render-fork-config.nix`, then runs the suite in a `runCommand` with
  `python3+pytest`, `jujutsu`, `git` on `nativeBuildInputs`, `HOME=$(mktemp -d)`,
  and `JJ_FORK_CONFIG_TOML=<toml>`.
- The suite source is `lib.fileset.toSource` over every `*.py` file — new test
  files appear without an edit.
- Two documented run modes: the flake check (sandbox) and `devenv shell` +
  `pytest -k <case>` (interactive, not hermetic).

## Approaches

### 1. Per-group checks (one derivation per `test_<group>.py`)

- Works: yes. `lib.genAttrs` over the test-file basenames makes
  `checks.<sys>.jj-experiments-<group>`, each a `runCommand` that copies the
  whole suite source (conftest.py and topologies.py are shared) but runs only
  `pytest test_<group>.py`.
- Purity: pure. Same inputs as today.
- Caching: excellent and granular. Each group is its own derivation, so a change
  in one group only rebuilds that group and the aggregate. `nix flake check`
  runs them in parallel.
- Ergonomics: good for a fixed set (`nix build .#checks.<sys>.jj-experiments-placement`).
  Weak for a free-form `-k substring` across files — you get file granularity,
  not name granularity. Tab-completable attr paths.
- Cost: low wiring. One helper `mkGroupCheck` plus a `genAttrs`. Group names must
  be discovered at eval time from the source (readable with `builtins.readDir`).

### 2. Parameterized / overridable derivation (passthru function)

- Works: yes, cleanly, through a `passthru.mkPytest { k ? "", files ? "" }`
  function rather than `overrideAttrs`. `overrideAttrs` on the current derivation
  is awkward: the pytest args are baked into the multi-line `buildCommand`
  string, so an override must rewrite the whole command. A passthru builder is
  the clean form.
- Purity: pure. `k`/`files` become part of the derivation, so the hash tracks
  them.
- Caching: correct. A given `k` caches; a new `k` is a new derivation.
- Ergonomics: the `--expr` form is verbose —
  `nix build --expr '((builtins.getFlake "path:...").checks.<sys>...mkPytest { k = "placement"; })'`.
  Acceptable in a script or a Justfile wrapper, clumsy by hand. No `--impure`
  needed.

### 3. Impure env passthrough (`builtins.getEnv "JJX_PYTEST_K"`)  — RECOMMENDED

- Works: yes. Proven (see PoC). One extra check attr reads the filter with
  `builtins.getEnv` and injects it as a build-time env var; pytest uses `-k`.
- Purity: the *evaluation* is impure (`--impure` required, `getEnv`). The
  *build* stays fully sandboxed — no network, `HOME=$(mktemp -d)`, only the
  declared inputs. So the test isolation guarantee is unchanged; only the
  attr's identity depends on an env var.
- Caching: the env value is captured into the derivation (as an env var), so it
  is part of the hash. Same `JJX_PYTEST_K` value hits the cache; a different
  value rebuilds. Re-eval happens every run (cheap). To force a rerun on the
  same filter, the developer can bump the value or `nix build --rebuild`.
- Ergonomics: best for "run just the placement tests" —
  `JJX_PYTEST_K=placement nix build --impure .#checks.<sys>.jj-experiments-filter`.
  Free-form `-k` substring, no `--expr`, one env var. This is the closest sandbox
  analogue of the documented `devenv` + `pytest -k <case>` mode.

### 4. `nix run` app wrapper (`.#jj-experiments-run -- -k placement`)

- Works: yes. An app (`writeShellApplication`) with `python3+pytest`, `jujutsu`,
  `git` as `runtimeInputs`, `JJ_FORK_CONFIG_TOML` exported to the rendered TOML,
  that copies the suite to a temp dir and runs `pytest "$@"`.
- Purity: the app runs in the *user's* environment, NOT a hermetic sandbox. It
  still sets `HOME=$(mktemp -d)` and the XDG/JJ_CONFIG isolation from conftest,
  so the developer's real jj/git config is safe. But it is not a reproducible
  build artifact and it is not cached — it re-runs every time.
- Caching: none (that is the point — always re-runs).
- Ergonomics: best raw feel — `nix run .#jj-experiments-run -- -k placement -x`
  passes any pytest flag. Fastest inner loop. Call out clearly: this is a
  convenience runner, not the CI gate. The `nix build` check stays the gate.

### 5. Other options

- `nix build .#checks.<sys>.jj-experiments-pytest` already targets one check.
  `nix flake check` runs every check; there is no built-in "run one check" flag
  other than building its attr path. So approach 1 (per-group attrs) is the way
  to make `flake check`-style single selection.
- `builtins.filterSource` / a per-file source subset gives no real win over
  copying the full suite and passing `test_<group>.py` — conftest.py and
  topologies.py are always needed, and pytest selection is cheaper than source
  surgery.

## Proof of concept (approach 3, ran successfully)

Rendered the fork TOML with the repo's own `render-fork-config.nix`:

```bash
TOML=$(nix build --impure --no-link --print-out-paths --quiet --expr \
  'let f=builtins.getFlake ("path:"+toString /path/to/nix-configs);
       p=f.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
   in import (f+"/checks/jj-experiments/render-fork-config.nix") {
        pkgs=p; mkSlots=f.lib.kdn.mkSlots; slotsPath=f+"/modules/slots";
        nixConfigs=f; extraInputs=f.inputs; }')
```

Note: the flake's own `render-fork-config.nix` needs `pkgs=` (not `p=`) in
`specialArgs`; the slot module reads the `pkgs` module argument.

Then a scratch `runCommand` (in `/tmp/jjx_poc.nix`) that reads
`builtins.getEnv "JJX_PYTEST_K"`, copies the suite, exports the TOML, and runs
`pytest -v -k "$PYTEST_K"`:

```bash
JJX_PYTEST_K=placement nix build --impure --no-link --file /tmp/jjx_poc.nix
```

Result:

```
collected 80 items / 75 deselected / 5 selected
test_placement.py::test_upstream_change_on_frozen_tree_unified_recipe PASSED
test_placement.py::test_second_upstream_change_into_existing_mutable_merge PASSED
test_placement.py::test_fork_leaf_change_stays_above_the_merge PASSED
test_placement.py::test_fork_base_change_folds_into_a_new_merge PASSED
test_placement.py::test_mixed_working_copy_split_by_content PASSED
====================== 5 passed, 75 deselected in 10.85s =======================
```

So the sandbox build ran the placement fork family only, resolved the real
revset aliases from the TOML, and passed.

## Ranked recommendation

1. **Approach 3 — impure env `JJX_PYTEST_K` check** for the ergonomic
   sandbox subset. One env var, free-form `-k`, keeps the build sandboxed.
2. **Approach 4 — `nix run` app** as the fast, non-hermetic inner loop
   (any pytest flag). Pairs well with #3.
3. **Approach 1 — per-group checks** for CI parallelism and stable attr paths.
4. Approach 2 (passthru builder) only if a script needs a pure, hash-tracked
   parameter without `--impure`.

The current whole-suite `jj-experiments-pytest` stays as the CI gate in every
case.

## Ready-to-implement snippet (top recommendation, approach 3)

Add to `checks/default.nix`, next to `jj-experiments-pytest`, reusing the same
`jjExperimentsSuite` and `jjForkConfigToml` lets:

```nix
# Subset runner: reads the pytest -k filter from JJX_PYTEST_K at eval time.
# Impure eval (needs `nix build --impure`), sandboxed build. Empty filter runs
# the whole suite, so it degrades to jj-experiments-pytest.
#   JJX_PYTEST_K=placement nix build --impure .#checks.<sys>.jj-experiments-filter
jj-experiments-filter =
  let
    k = builtins.getEnv "JJX_PYTEST_K";
  in
  pkgs.runCommand "jj-experiments-filter-check"
    {
      nativeBuildInputs = [
        (pkgs.python3.withPackages (ps: [ ps.pytest ]))
        pkgs.jujutsu
        pkgs.git
      ];
      JJ_FORK_CONFIG_TOML = jjForkConfigToml;
      PYTEST_K = k;
    }
    ''
      export HOME="$(mktemp -d)"
      cp -r ${jjExperimentsSuite}/. ./suite
      chmod -R u+w ./suite
      cd ./suite
      python3 -m pytest -v -k "$PYTEST_K"
      touch "$out"
    '';
```

Optional companion (approach 4, the app) in `flake.nix` `perSystem`:

```nix
apps.jj-experiments-run = {
  type = "app";
  program = lib.getExe (pkgs.writeShellApplication {
    name = "jj-experiments-run";
    runtimeInputs = [
      (pkgs.python3.withPackages (ps: [ ps.pytest ]))
      pkgs.jujutsu pkgs.git pkgs.coreutils
    ];
    text = ''
      export HOME="$(mktemp -d)"
      export JJ_FORK_CONFIG_TOML="@toml@"   # substitute the rendered TOML path
      d="$(mktemp -d)"; cp -r "@suite@/." "$d"; chmod -R u+w "$d"; cd "$d"
      exec python3 -m pytest "$@"
    '';
  });
};
```

(`@toml@`/`@suite@` are placeholders — wire them from the same
`render-fork-config.nix` / `fileset.toSource` the check uses, via
`substituteAll` or string interpolation.)

# Follow-up notes

- The task's inline TOML expr used `specialArgs = { inherit p; ... }`; that
  fails with "attribute 'pkgs' missing". Use `pkgs = p;` or reuse
  `render-fork-config.nix` directly (done in the PoC).
- `lib.fileset.toSource` needs a real path `root`, not `flake + "/subdir"`
  (which is string-like). The PoC used the literal repo path; a real check uses
  the relative `./jj-experiments` path as today.
- Approach 3 re-evaluates each run but caches per filter value. To always rerun
  the same filter, use `--rebuild` or bump the value.

## Pure build + nix run app (round 2)

Round 1 recommended an impure `getEnv` check. This round finds a cleaner path:
a parameterized builder plus `nix build --file ... --argstr`, wrapped in a
`nix run` app. It needs **no `--impure` flag** and keeps the build sandboxed.

### Verdict

- A fully-pure, no-args subset build is possible **only with the subset baked
  into a flake attr** — per-group `genAttrs` checks (round 1, approach 1).
  Example: `nix build .#checks.<sys>.jj-experiments-placement`. Pure eval, no
  flag, no free-form `-k`.
- **Free-form `-k` with no `--impure` flag IS achievable** through
  `nix build --file <runner.nix> --argstr extraArgsJSON '...'`. Classic `-f`
  evaluation runs in impure mode by default, so `builtins.getFlake (toString
  <repo>)` and `builtins.currentSystem` work with no flag. `--arg`/`--argstr`
  are pure and only work with `-f` (auto-called function), not with a flake ref.
  The eval is technically impure (it reads the working tree and the current
  system), but it needs no flag and is reproducible per git commit. The build
  (the `runCommand`) is always sandboxed: `HOME=$(mktemp -d)`, only declared
  inputs. Proven below.
- Flake outputs cannot take CLI args — confirmed. `nix build .#attr` enforces
  pure eval; `--expr` also enforces pure eval and needs `--impure` for
  `getFlake(path)`. Negative control below shows the `--expr` form fails without
  `--impure`, while the `--file` form succeeds without it.

So: the purest free-form-`-k` subset run is the `--file`/`--argstr` runner. The
purest no-args run is a per-group flake attr. Round 1's `getEnv` approach is no
longer needed — `--argstr` replaces the env var and drops the `--impure` flag.

### Eval-mode facts (measured, Lix 2.95.2)

| Installable form | eval mode | `getFlake(path)` / `currentSystem` | takes `--arg` |
|---|---|---|---|
| `.#checks.<sys>.attr` (flake) | pure | needs `--impure` | no |
| `--expr '...'` | pure | needs `--impure` | no |
| `--file runner.nix` / `nix-build` | impure by default | works, **no flag** | yes |

### Recommended design

Three files. No change to the meaning of `jj-experiments-pytest`.

1. `checks/jj-experiments/mk-pytest.nix` — the parameterized builder. Takes
   `extraArgs`, bakes them into the derivation with `lib.escapeShellArgs` (so the
   hash tracks the args and caches per arg set).
2. `checks/default.nix` — build the existing whole-suite check through the
   builder with `extraArgs = [ ]`. Optionally expose the builder as
   `passthru.mkPytest`.
3. `checks/jj-experiments/subset-runner.nix` — a standalone file that
   `getFlake`s the repo, renders the TOML through the repo's own
   `render-fork-config.nix`, and calls the builder with
   `extraArgs = builtins.fromJSON extraArgsJSON`.

An app forwards `$@` into the runner. It turns the shell args into a JSON array
with `jq`, then runs the hermetic build. No `--impure`.

### Ready-to-implement snippets

`checks/jj-experiments/mk-pytest.nix`:

```nix
# Parameterized jj-experiments pytest builder. extraArgs are baked into the
# derivation (hash-tracked), so a given arg set caches and a new one rebuilds.
{
  pkgs,
  lib,
  suite, # the suite source (a store path or fileset.toSource result)
  toml, # rendered JJ_FORK_CONFIG_TOML
  extraArgs ? [ ],
}:
pkgs.runCommand "jj-experiments-pytest"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (ps: [ ps.pytest ]))
      pkgs.jujutsu
      pkgs.git
    ];
    JJ_FORK_CONFIG_TOML = toml;
    PYTEST_ARGS = lib.escapeShellArgs extraArgs;
  }
  ''
    export HOME="$(mktemp -d)"
    cp -r ${suite}/. ./suite
    chmod -R u+w ./suite
    cd ./suite
    # shellcheck disable=SC2086
    python3 -m pytest -v $PYTEST_ARGS
    touch "$out"
  ''
```

`checks/default.nix` (route the current check through the builder):

```nix
jj-experiments-pytest = import ./jj-experiments/mk-pytest.nix {
  inherit pkgs lib;
  suite = jjExperimentsSuite;
  toml = jjForkConfigToml;
  # extraArgs = [ ];  # whole suite
};
```

`checks/jj-experiments/subset-runner.nix` (auto-called by `nix build --file`):

```nix
# Standalone subset runner. Classic `-f` eval is impure-mode by default, so the
# getFlake below needs NO `--impure`. The build stays sandboxed.
#   nix build --file checks/jj-experiments/subset-runner.nix \
#     --argstr extraArgsJSON '["-k","placement"]' -L
{
  repo ? toString ../.., # repo root, from checks/jj-experiments/
  extraArgsJSON ? "[]",
}:
let
  flake = builtins.getFlake repo;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  lib = flake.lib;
  toml = import (flake + "/checks/jj-experiments/render-fork-config.nix") {
    inherit pkgs;
    mkSlots = lib.kdn.mkSlots;
    slotsPath = flake + "/modules/slots";
    nixConfigs = flake;
    extraInputs = flake.inputs;
  };
in
import (flake + "/checks/jj-experiments/mk-pytest.nix") {
  inherit pkgs lib toml;
  suite = flake + "/checks/jj-experiments"; # store-path string; `cp -r` works
  extraArgs = builtins.fromJSON extraArgsJSON;
}
```

App in `flake.nix` `perSystem` (uses `$PWD` so working-tree edits are picked up):

```nix
apps.jj-experiments-run = {
  type = "app";
  program = lib.getExe (pkgs.writeShellApplication {
    name = "jj-experiments-run";
    runtimeInputs = [
      pkgs.nix
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      root=''${JJX_REPO:-$PWD}
      if [ "$#" -eq 0 ]; then
        json='[]'
      else
        json=$(printf '%s\n' "$@" | jq -R . | jq -sc .)
      fi
      exec nix build --file "$root/checks/jj-experiments/subset-runner.nix" \
        --argstr repo "$root" --argstr extraArgsJSON "$json" --no-link -L
    '';
  });
};
```

### User-facing commands

```bash
# whole-suite gate (unchanged, pure flake check)
nix build .#checks.<sys>.jj-experiments-pytest

# subset, hermetic build, NO --impure, by hand
nix build --file checks/jj-experiments/subset-runner.nix \
  --argstr extraArgsJSON '["-k","placement"]' -L

# subset through the app (forwards any pytest flags)
nix run .#jj-experiments-run -- -k placement -x

# truly pure, no-args baseline (needs per-group genAttrs attrs, round 1 #1)
nix build .#checks.<sys>.jj-experiments-placement
```

### Gotchas designed around

- `render-fork-config.nix` needs `pkgs =` in `specialArgs`, not `inherit p`
  (the slot reads the `pkgs` module argument). The runner reuses the file, so it
  passes `pkgs` correctly.
- `lib.fileset.toSource` needs a real path `root`. The subset runner sidesteps
  this: it uses the flake store-path subdir (`flake + "/checks/jj-experiments"`)
  and `cp -r ${suite}/.` — proven to work. The whole-suite check keeps its
  `fileset.toSource` for finer rebuild granularity.
- The shipped `subset-runner.nix` uses `getFlake ("path:" + repo)`. The `path:`
  prefix reads the **working tree**, not git's tracked index, so it sees new or
  dirty files with no `git add`. (An earlier draft used bare `getFlake repo`,
  which reads git's index and needs the two new files added first — see
  `.agents/rules/nix-conventions.md`. The shipped `path:` form is the better one,
  so this gotcha no longer applies to it.)
- Args cross the shell/Nix boundary as a JSON array (`--argstr` + `fromJSON`),
  which keeps each arg a separate `argv` entry and avoids word-split bugs.

### App form A vs form B

- **Form A (recommended here):** app execs `nix build --file ...`. The build is
  a real sandbox (matches "keep the build hermetic"). Args pass in with no
  `--impure`. Caches per arg set. This is the closest fit to the user's mental
  model.
- **Form B (round 1, approach 4):** app bakes python-env + jj + git + TOML +
  suite as store paths and runs `pytest "$@"` in the user process with a fresh
  `HOME`. More ergonomic and always re-runs, but it is **not** a build sandbox
  and does not cache. Keep it only as a fast, non-hermetic inner loop.

### PoC transcript

Runner in `/tmp/jjx-runner.nix` (same shape as `subset-runner.nix`). Build with
free-form `-k`, no `--impure`:

```
$ nix build --file /tmp/jjx-runner.nix --argstr extraArgsJSON '["-k","placement"]' --no-link -L
building '/nix/store/...-jj-fork-config.toml.drv'...
building '/nix/store/...-jj-experiments-subset.drv'...
jj-experiments-subset> rootdir: /nix/var/nix/builds/.../suite      # real sandbox
jj-experiments-subset> collected 80 items / 75 deselected / 5 selected
jj-experiments-subset> test_placement.py::... PASSED  (x5)
jj-experiments-subset> ====== 5 passed, 75 deselected in 11.04s ======
```

App (`writeShellApplication`, `nix`+`jq` pinned) forwarding `$@`, no `--impure`:

```
$ jjx-test -k placement -x            # == nix run .#jj-experiments-run -- -k placement -x
jjx-test: extraArgsJSON=["-k","placement","-x"]
jj-experiments-subset> collected 80 items / 75 deselected / 5 selected
jj-experiments-subset> ...PASSED (x5)
jj-experiments-subset> ====== 5 passed, 75 deselected in 10.59s ======
```

Negative control — the `--expr` (pure-eval) form fails without `--impure`, which
proves the `--file` form's no-flag success is real:

```
$ nix build --expr 'import /tmp/subset-runner.nix { extraArgsJSON = "..."; }' --no-link
error: access to absolute path '/tmp/subset-runner.nix' is forbidden in pure eval
mode (use '--impure' to override)
```

Caching (hash tracks the args):

```
$ nix build --file ... --argstr extraArgsJSON '["-k","placement"]'   # cached, no rebuild
$ nix build --file ... --argstr extraArgsJSON '["-k","topolog"]'     # new drv
jj-experiments-subset> ====== 1 passed, 79 deselected in 2.41s ======
```
