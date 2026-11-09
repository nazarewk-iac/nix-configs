---
type: Reference
description: Web research (2026-11-09) on speeding up Nix host evaluation, from primary sources (nix-eval-jobs README, Nix 2.35 nix.conf manual). Ideas, the pinning-vs-parallelism trade-off, and what to measure next.
timestamp: 2026-11-09T12:30:00+01:00
---

# Web research — speeding up host evaluation (2026-11-09)

Primary sources read:

- [`NixOS/nix-eval-jobs` README](https://github.com/NixOS/nix-eval-jobs) (parallel evaluator; the
  engine Hydra, **colmena**, and `nix-fast-build` use).
- [Nix 2.35 `nix.conf` manual](https://nix.dev/manual/nix/latest/command-ref/conf-file) (settings
  relevant to evaluation).

Companion to [research.md](research.md) (local flamegraph) and
[machine-differences.md](machine-differences.md) (per-host spread). Not yet measured here — every
idea below is tagged with the measurement it needs.

## Idea 1 — evaluate hosts in parallel with `nix-eval-jobs`

`nix-eval-jobs` evaluates an attribute set with **N worker processes**, each restarted when its RSS
exceeds `--max-memory-size`; `workers * max-memory-size` is one memory budget. Each JSON line
carries `stats.wallMs` and `stats.allocBytes` for that attribute, so it also reports *which host is
slow* rather than only an aggregate. Relevant flags: `--flake`, `--workers`, `--max-memory-size`,
`--no-instantiate` (evaluate without writing `.drv`, faster), `--eval-store`, `--check-cache-status`,
`--reference-lock-file`.

Our repo already depends on the same machinery: **colmena uses `nix-eval-jobs`**, and we have the
`nix-fast-build` input. So a fleet eval could be:

```
nix-eval-jobs --flake .#nixosConfigurations --workers "$(nproc)" --max-memory-size $(( mem/workers ))
```

**Trade-off to verify (important):** `nix-eval-jobs` uses **separate processes**, so it does **not**
share a memoised nixpkgs across hosts. That is the *opposite* of the lever in the pkgs-pinning task
(one `pkgs` value shared in **one** process). So:

- Big many-core machine, independent hosts → **parallel workers** win on wall time.
- The pinning lever wins only inside **one** process (or with `--workers 1`), where all hosts reuse
  one evaluated `pkgs`.

Measure both: (a) `nix-eval-jobs --workers 1` vs `--workers N` on all six hosts; (b) the
single-process multi-host `nix eval` (the ~90 s observation) with and without pinned pkgs. The right
answer may be *per-host isolation for CI* (parallel) and *pinned single-process for local fleet
checks* — different tools for different goals.

## Idea 2 — stop defeating the flake evaluation cache

`eval-cache` is on by default (`nix.conf`): a command will not re-evaluate on a **second invocation
with the same flake version**. Our measurements use `builtins.getFlake "path:$PWD"`, which
**copies the tree into the store every run** → a fresh store path/version → **cache miss every
time**, and it inflates wall time. Use a stable flake reference (`.#`, or `git+file://` with
`--reference-lock-file`) so repeated evals hit the cache. Measure: repetitive warm eval of one host
via `.#host` vs `path:`.

## Idea 3 — forbid IFD in the host path

`allow-import-from-derivation = false` makes evaluation throw if it needs a build. We already killed
the one eval-time IFD (`kdn-authorized-keys`, commit `bda0ba4d`). Setting this in CI/measurement
**proves** the host eval needs no builder — a cheap regression guard for the "wall ≫ CPU" and
"eval depends on a build" issues.

## Idea 4 — built-in eval profiler

Nix 2.35 offers `eval-profiler = flamegraph` (+ `eval-profile-file`, `eval-profiler-frequency`)
without an external profiler. research.md recorded Lix as lacking an eval profiler; this is a reason
to test a **CppNix/Lix-2.35 client against the Lix daemon** on a throwaway host to obtain a real
flamegraph of the module graph (the devenv overlay / specialisations cost centres). Verify the flag
exists on the client we actually ship before relying on it.

## Idea 5 — smaller knobs worth one measurement each

- `max-jobs` / `cores`: eval is single-threaded per process; these affect the *build*, not eval.
  Not a lever for eval wall time (confirm and stop attributing eval time to them).
- `--no-instantiate`: for pure eval timing, drop `.drv` writing (compare to the drvPath timing).
- `filetransfer-retry-*`, `connect-timeout`: reduce flaky-network stalls in cold evals (the
  wall≫CPU gap partly), not the language eval.
- `eval-attrset-update-layer-rhs-threshold`: micro memory tuning; leave at default unless a
  flamegraph points at attrset-update allocation.

## Ranked recommendation (after research, before measurement)

1. **L1 — reduce specialisations** (from machine-differences.md): each `specialisation.*` re-evaluates
   the whole module graph and is *inside* `config.system.build.toplevel`. brys has four. This is the
   biggest single host-eval cost and none of the above touches it.
2. **Idea 1** for CI/fleet wall time on many cores; **Idea 2** to make our own measurements honest.
3. **Pinning (L2)** only for the single-process shared case; it complements, not replaces, parallelism.
4. Idea 3 as a guard, Idea 4 for a real flamegraph, Idea 5 as quick confirmations.

Every item needs a measured number before it is called a win. The harnesses are `hack/eval-profile.sh`,
`hack/eval-compare.sh`, `nix-eval-jobs`, and `nix eval .#<host>` (not `path:`).
