---
type: Status
description: The research and the design are complete; no cut has landed yet, and the host-evaluation exit criterion is untouched.
task: definition.md
authored_by: agent
timestamp: 2026-09-11T22:00:00+02:00
---

# Evaluation performance — status

## Done so far

- [research.md](research.md) is complete. It names every profiler this machine has, one real
  flamegraph of host `anji`, the top cost centres, and the protocol for a fair tree comparison.
- [design.md](design.md) is complete. It designs the measurement harness, the runnable comparison
  and one optimisation, each with an acceptance number.
- The harness lands with this design: `hack/eval-profile.sh`, `hack/eval-profile-rank.py` and
  `hack/eval-compare.sh`.

## Remaining

- **Exit criterion 1 is untouched.** A warm `anji` evaluation still costs about 64 s. No cut to a
  host evaluation has landed.
- The two large host-side levers are unstarted: the devenv overlay on a host `pkgs`, about 17 % of
  self time, and the `nix-rosetta-builder` disk-image reference, about 31 %. Both change host
  output, so both need a closure proof and not a `drvPath` proof.
- The tree comparison is written but **not run**. The two trees are not at feature parity.
- The `denLib.pairModules` lever **landed** as `perf(checks): resolve every den pair from one
  evaluation`, and it touches `checks/den-mvp/tests.nix` alone. `den-eval-instantiate` passes 1 of 1
  assertions. Its 250 s acceptance number stays **unmeasured**: the one run after the change took
  909 s against a 358.0 s baseline, and a cold store after a 142 GB garbage collection confounds
  that number. Re-measure on a warm store before you read it as either a win or a loss.
- The other 79 `denLib.imports` call sites under `checks/` still start one den library evaluation
  each.

## Next directions

1. Run the harness once on an idle machine and record the ranked table in `.worklog.md`. That gives
   the before-measurement that every later cut needs.
2. Take the devenv-overlay lever next. It is the largest cut that does not need new machinery. Prove
   sameness with a closure comparison, never with a `drvPath`.
3. Leave the tree comparison blocked until the `generalization` umbrella task reports parity.

**The blocker for the comparison is named:** feature parity between `modules/universal` and
`modules/den/aspects`. Track it in [../generalization/definition.md](../generalization/definition.md).
