---
type: Task
description: Cut host evaluation time in this repo, and set up a fair evaluation-cost comparison between the universal tree and the den tree.
status: in-progress
authored_by: agent
timestamp: 2026-09-11T17:00:00+02:00
---

# Evaluation performance

A full host evaluation in this repo costs about a minute of wall clock. A cold run costs four
minutes. That cost lands on every build, every check bundle and every agent loop. This task
finds the cost, cuts it, and keeps it cut.

The measured start point is in [research.md](research.md). Read it first. It names the
profilers this machine has, the profilers it does not have, and the top cost centres.

## Numbers that define the problem

One `darwinConfiguration` toplevel `drvPath` evaluation for host `anji`, measured 2026-09-11 on
Lix 2.95.2, `aarch64-darwin`:

| Run | Wall | User | Sys | Peak RSS |
|---|---|---|---|---|
| Cold, first run of the day | 243.7 s | 28.9 s | 9.3 s | 5.57 GB |
| Warm, repeated | 64.1 s | 23.7 s | 8.6 s | 5.13 GB |

Two gaps drive the task:

1. **Wall clock is about twice the evaluator CPU.** 64 s wall against 32 s of user plus system
   time. The rest is store round-trips and input refetch, not language evaluation.
2. **Three nixpkgs trees evaluate in one host evaluation.** The repo's own nixpkgs carries 72.5 %
   of the function calls. A second, devenv-patched nixpkgs carries 17.1 %. The devenv flake
   itself carries 7.9 %. The repo's own module code carries 0.08 %.

## Goal

Cut the wall clock of one warm host evaluation. The target is the 64 s warm figure above, on the
same machine, with the same host and the same nixpkgs revision.

The task keeps its goal independent of the module-tree question. Whichever tree the repo keeps —
`modules/universal` or `modules/den/aspects` — the evaluation must get faster.

## Scope

In scope:

- Measure where evaluation time goes. Use the mechanisms in [research.md](research.md).
- Remove work that a host evaluation does not need. The devenv overlay on a host `pkgs` is the
  first candidate.
- Remove import-from-derivation from the host evaluation path, or prove it is unavoidable.
- Close the wall-clock-to-CPU gap, or explain it.
- Build the parity-gated comparison between the two module trees. See the next section.

Out of scope:

- A change to nixpkgs itself.
- A change that alters any host's built output. Every cut must keep the same system closure.
- A rewrite of either module tree. This task measures the trees; it does not port between them.

## Deliverable: the parity-gated tree comparison

`modules/universal` plus `modules/meta` is the old tree: 194 plus 3 files, `specialArgs` through
`kdnConfig`, and a recursive `listFilesRecursive` auto-loader. `modules/den/aspects` is the new
tree: 105 files, no `specialArgs`, exposed as `denConfigurations`.

The repo must know which tree costs less to evaluate. The comparison is a deliverable of this
task, not an aside. [research.md](research.md) § "Part 3" holds the full protocol: what to hold
constant, what to measure, how many repeats, and the confounds a naive run hits.

**The comparison runs only after the two trees reach close feature parity.** Until then a
measurement compares a complete tree against an incomplete one, and the incomplete tree wins for
the wrong reason. Track the parity state in the `generalization` umbrella task.

## Exit criteria

The task is done when all of these hold:

1. A warm host evaluation of `anji` costs less than 40 s wall clock on this machine. That is a
   37 % cut against the 64.1 s baseline.
2. Every host in `hosts/` still evaluates, and `bundle-core` still passes.
3. No host's built system closure changes because of a cut made here. Prove it with a
   `nix-diff` or a closure comparison, **not** with a `drvPath` equality. `drvPath` equality is
   invalid in this repo; see the caveat below.
4. The parity-gated tree comparison protocol is written, reviewed, and either run or explicitly
   deferred with a named blocker.
5. Every cut has a recorded before-and-after measurement in `.worklog.md`.

## The `drvPath` caveat

Do not prove a no-change refactor with `drvPath` equality in the universal tree. `kdnConfig.self`
reaches the evaluated config, so any edit anywhere in the repo changes every host's `drvPath`.
`denConfigurations` never reads `self`, so a den-side `drvPath` comparison is valid. For the
universal tree, compare option values or compare the closure of the built system.

## Related

- [../generalization/definition.md](../generalization/definition.md) — the umbrella task that
  drives the two trees toward parity.
- [../../../../checks/README.md](../../../../checks/README.md) — the check bundles and their
  measured times. `den-eval-instantiate` costs 358 s for 201 pairs in one single-threaded
  evaluator, so a cut here pays back there too.
