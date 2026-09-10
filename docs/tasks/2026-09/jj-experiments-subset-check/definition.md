---
type: Task
description: Let a developer run a subset of the jj-experiments pytest suite through the nix build runner, instead of the whole suite only.
status: in-progress
authored_by: agent
timestamp: 2026-09-03T00:00:00+02:00
---

# Run a subset of jj-experiments through nix build

Research: [research.md](research.md).

## Goal

`checks.<system>.jj-experiments-pytest` always runs the whole pytest suite. A developer who works
on one test group needs a hermetic run of that group only, with a `-k` filter or one test file. The
whole-suite check must keep its present meaning.

## Current state

The research answers the question: a subset runs cleanly in the Nix sandbox, and the proof of
concept ran 5 placement tests through a `runCommand`. It ranks the approaches and recommends a
standalone subset runner that takes the pytest arguments as a build argument.

The recommendation is in the tree:

- `checks/jj-experiments/subset-runner.nix` — the parameterized runner.
- `flake.nix:465-486` — the `jj-experiments-run` app, which turns its arguments into a JSON array
  and calls the runner.
- `checks/default.nix:77` points at both.

Nothing records an exit test run against the current tree, so the task stays in progress.

## Exit test

- `nix run '.#jj-experiments-run' -- -k <filter>` runs only the selected tests and passes.
- The run needs no `--impure` flag, and the build stays sandboxed.
- Two different argument sets produce two derivations, and a repeated argument set hits the cache.
- `nix flake check` still runs the whole suite, unchanged.
