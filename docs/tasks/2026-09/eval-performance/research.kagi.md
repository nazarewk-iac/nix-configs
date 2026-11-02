---
type: Research
description: Secondary digest of a Kagi Assistant session on Nix evaluation speed, organised by theme with every claim marked unverified on this repo's hardware.
task: definition.md
authored_by: agent
timestamp: 2026-10-30T15:10:35+01:00
---

# Kagi research — a secondary source

> **This is a secondary source. It is not a measurement of this repo.**
>
> The material below comes from one Kagi Assistant session, dated 2026-09-11. The assistant
> answered questions and cited web pages with reference numbers such as `[^7]`. It did not run
> anything on this machine. It did not see this repo.
>
> Treat every number here as a **claim to check**, not as a result. [research.md](research.md) holds
> the measurements taken on this hardware. Read that first. Read this file only for the new avenues
> it names, and then measure each one here before you act.
>
> One fact is verified on this machine today: the system evaluator is **Lix 2.95.3**
> (`nix --version` → `nix (Lix, like Nix) 2.95.3`). Note that [research.md](research.md) measured on
> Lix 2.95.2, one patch release earlier.

The session has five turns:

1. General options to analyse and improve evaluation time.
2. The same question for a Lix daemon, with a non-Lix client considered.
3. Alternative clients and evaluators.
4. Single-host updates, where fleet updates are not a priority. This turn matches this repo.
5. Whether `fix` gives surgical profiling.

The digest below regroups the claims by theme, then tabulates them, then states what they mean here.

---

## 1 — Profiling tools

| Tool                                                       | What the session claims                                                                                                                                                                              | Reference            |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------- |
| `--eval-profiler flamegraph`                               | Samples the function call stack. Writes folded stacks for `flamegraph.pl` and speedscope. Settings: `--eval-profiler flamegraph`, `--eval-profile-file`, `--eval-profiler-frequency` (default 99 Hz) | `[^3]` `[^4]` `[^5]` |
| Availability                                               | **CppNix ≥ 2.30 only.** The session first says it is "available in upstream Nix and Lix" `[^3]`, then corrects itself in turn 2: "There is no flamegraph eval profiler in Lix as of 2.95"            | `[^11]`              |
| `NIX_SHOW_STATS`, `NIX_COUNT_CALLS`, `NIX_SHOW_STATS_PATH` | Present in all Nix versions, **including Lix**. Give allocation, thunk and call counts. No flame graph                                                                                               | `[^7]` `[^9]`        |
| `nix-evaluator-stats`                                      | A community web dashboard for `NIX_SHOW_STATS` JSON. Has a snapshot-compare mode to diff two runs. Works with Lix because it only reads the JSON                                                     | `[^8]` `[^10]`       |
| speedscope.app                                             | Interactive viewer. The "Sandwich View", filtered on `derivationStrict`, ranks derivations                                                                                                           | `[^5]`               |
| eBPF USDT probes                                           | Lix 2.93 added USDT probes for production instrumentation. Aimed at Lix developers, not config profiling                                                                                             | `[^8]`               |

[research.md](research.md) already proved the first and third rows on this machine. The new item is
`nix-evaluator-stats`. It is a viewer, not a profiler, so it cannot show self time either.

---

## 2 — Determinate Nix: parallel evaluation and lazy trees

The session gives this section twice, and the two versions disagree. Keep both.

**First version (turn 1):** parallel evaluation `[^13]` `[^14]` and lazy trees `[^17]` are
Determinate-only features. The session puts them "in the daemon".

**Correction (turn 3, stated by the session itself):**

> "Parallel evaluation and lazy trees are **client-side, not daemon-side**. I earlier said
> Determinate Nix's speedups live in the daemon and wouldn't carry over to a Lix daemon. That was
> wrong."

The corrected argument:

- Determinate Nix has a modified `nix` **CLI** and a separate `Determinate Nixd`. Nixd handles
  garbage collection and store mounting, not store service `[^1]` `[^2]`.
- Parallel evaluation changes the evaluator's thunk handling and data structures. It says nothing
  about the store or the daemon `[^3]`.
- So a Determinate or upstream Nix ≥ 2.35 **client** against a Lix **daemon** is plausible. The
  session found no report that confirms it, and says to test it first.
- The Lix wire protocol is frozen at CppNix 2.18 `[^1]`, so a current CppNix client speaks it.
  [research.md](research.md) already ran a CppNix 2.35.2 client against the Lix daemon with no
  protocol error. That confirms the protocol part, not the parallel-eval part.

**Lazy trees, corrected:** Nix 2.35 (2026-06-22) hashes flake sources without copying them to the
store, unless `.outPath` reaches a derivation. It also makes `fetchTarball` lazy and reports about
2× faster fetch and unpack of a nixpkgs tarball `[^4]`. This is upstream's own design, not
Determinate's virtual filesystem. Full lazy-tree behaviour needs `lazy-locks`, which the session says
breaks compatibility with other Nix implementations and advises against for a Lix setup `[^12]`.

**Reported speedups, vendor-run:** 5× or more for parallel eval `[^14]`, 3× or more wall time and 20×
or more disk for lazy trees `[^17]`. The session itself calls these hints, not proof.

---

## 3 — Lix

| Claim                                                                                                                                                                                                                           | Reference |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Lix's evaluator is 8–20 % faster than CppNix 2.18 overall                                                                                                                                                                       | `[^5]`    |
| **Lix 2.96** (released 2026-10-13) links **mimalloc** for all non-GC allocations. Reported "5–12 % wall-clock improvement on evaluation workloads, from `nix-instantiate hello` to `nix-env -qa` and full NixOS configurations" | `[^7]`    |
| **Lix 2.95** launches sandboxed builds up to **80 % faster** on Linux. Helps graphs with many `runCommand` derivations. A build-phase gain, not eval                                                                            | `[^4]`    |
| Lix 2.96 releases an experimental **Cap'n'Proto** RPC protocol for local daemon connections. It runs beside the legacy protocol, so old clients keep working                                                                    | `[^4]`    |
| **No parallel evaluation** in Lix, confirmed absent mid-2026, no timeline                                                                                                                                                       | `[^12]`   |
| **No lazy trees** in Lix; the upstream implementation was rejected; a replacement is planned with no timeline                                                                                                                   | `[^5]`    |
| **No `--eval-profiler flamegraph`** in Lix, branched from 2.18, not backported                                                                                                                                                  | `[^11]`   |

A quoted nixpkgs eval benchmark `[^6]` gave these single-host times:

| Version                   | Time (s) |
| ------------------------- | -------- |
| lix-2.96 dev (2026-07-14) | 30.42    |
| lix-2.95.3                | 33.75    |
| lix-2.94.2                | 34.60    |
| nix-2.36 pre (2026-07-13) | 29.73    |
| nix-2.35.2                | 31.74    |
| nix-2.34.9                | 33.69    |

The session reads this as "Lix 2.95 and current CppNix are roughly on par". The mimalloc gap is
visible in the same table (2.96 dev 30.42 s against 2.95.3 33.75 s). This machine runs 2.95.3, so
the mimalloc gain is one release away, if the claim holds.

---

## 4 — `fix` (Zig evaluator)

The project is `psyclyx/fix` `[^10]`. It is a **from-scratch** evaluator in Zig, alpha quality.

| Feature                           | Claim                                                                                                                                           | Reference |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Evaluator                         | Parallel **lazy** evaluator with a **bytecode compile cache**                                                                                   | `[^10]`   |
| Worker protocol                   | Speaks the stable store worker protocol to CppNix and Lix daemons. Use `protocol=any` for Lix                                                   | `[^11]`   |
| `-Dprof-path`                     | A tree of thunk forcing. Total, self and estimated critical-path time per **body chunk**, which is roughly one Nix source location              | `[^2]`    |
| `--timeline`                      | Perfetto JSON with spans, worker quanta, GC pauses, demand waits and counters                                                                   | `[^1]`    |
| `--stats`                         | Heap, intern, chunk, scheduler and speculation counters on stderr                                                                               | `[^1]`    |
| `-Dthunks-log`, `fix thunks diff` | Per-thunk lifecycle log, compared across runs by `(file, line, col)`                                                                            | `[^1]`    |
| Debugger                          | Breakpoints, stepping, locals, backtraces, VM explorer                                                                                          | `[^1]`    |
| Limits                            | `local` and `auto` stores unsupported. `fix switch` experimental. Mainly tested on x86_64 Linux. Hooks need the exact CLI root the rebuild runs | `[^10]`   |

### Its own benchmark on one config

These numbers come from the `fix` project's own harness `[^1]` `[^3]`, not from this repo:

| Evaluator                         | Single NixOS config (ms) |
| --------------------------------- | ------------------------ |
| Determinate Nix 3.21.7, all cores | 3432                     |
| Nix 2.34.8                        | 2812                     |
| Lix 2.95.2                        | 2678                     |
| `fix` 0.3.0 (warm)                | about 890                |

The session reads this two ways, and both matter:

1. **Parallel eval is not a win for a single NixOS config.** Determinate with all cores was the
   **slowest** of the three. The `fix` README agrees: no evaluator wins every workload.
2. **`fix` itself reports about 3× on real-world desktop configs** in the same harness. That is the
   author's hardware and workload. The session could not see the workload contents `[^15]`.

The Home Manager variant looks the same `[^2]`. The provenance page dates the run 2026-08-09 on a
Ryzen 9 5950X `[^3]`.

### The safe test the session proposes

The `fix` project says any difference in values, derivations or store paths from Nix is a bug `[^10]`.
So use `fix` for **evaluation only**. Compare its `.drv` path with the normal one, and keep
`nixos-rebuild` for activation. A `.drv` equality gate is the safety test. This matches the
`drvPath` caveat in [definition.md](definition.md): the gate is valid on a den host, not on a
universal-tree host, because `kdnConfig.self` reaches the config there.

---

## 5 — Configuration-level items

| Item                                | Claim                                                                                                                                                        | Reference      |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------- |
| Duplicate nixpkgs imports           | The highest-impact config lever. Every separate nixpkgs import re-evaluates nixpkgs                                                                          | `[^9]`         |
| Home Manager as a NixOS module      | A second module-system evaluation, of similar size to NixOS. One user went from 30 s to 10 s after dropping it                                               | `[^4]`         |
| `home-manager.useGlobalPkgs = true` | Avoids a second nixpkgs import when HM runs as a NixOS module                                                                                                | `[^6]`         |
| Flake `packages` output access      | Reading a flake's `packages` from a NixOS config causes a hidden nixpkgs import                                                                              | `[^6]`         |
| `follows` on inputs                 | One thread cut evaluation from 3–4 min to about 2 min with `follows`, then to 1 min 15 s after one more patch removal; an `applyPatch` alone cost about 30 s | `[^11]`        |
| `documentation.enable = false`      | Stops manpage and HTML processing. A heavy hitter in a NixOS eval. The session found **no measured saving for this option alone**                            | `[^5]` `[^6]`  |
| Specialisations and containers      | **Each triggers a full extra NixOS module evaluation**                                                                                                       | `[^4]`         |
| Extra binary caches                 | Each is queried for missing paths before the build starts                                                                                                    | `[^4]`         |
| `with lib;`                         | Forces the whole attribute set. Explicit `lib.mkIf` access stays lazy                                                                                        | `[^10]`        |
| Import from derivation              | Runs a store build during evaluation. Sequential, blocks parallelism                                                                                         | `[^11]`        |
| Module count                        | 10–20 of your own modules is negligible against about 2,700 nixpkgs and about 1,200 HM modules. "Don't refactor files for speed"                             | `[^6]`         |
| `baseModules` trimming              | A smaller base list is possible but fragile. A community `nixosMinimal` uses about 185 modules                                                               | `[^2]` `[^12]` |

---

## 6 — `GC_INITIAL_HEAP_SIZE`

- The default initial heap is **384 MB** `[^9]`.
- A report says `GC_INITIAL_HEAP_SIZE=4G` cut `nix eval` wall time by **about 25 %** on a
  moderately sized NixOS config `[^9]`. The session gives no repo or measurement harness for it.
- A Nix commit `[^13]` changes the default to **80 % of free RAM, capped at 8 GiB**. The tracking
  issue `[^9]` was still open when the session looked, so the release is unknown.
- Lix may not honour the variable the same way. Boehm GC reads it, so it probably works, but the
  session says to test it `[^9]`.
- It trades RAM for speed. Under `sudo`, check that the variable survives `sudo` `[^9]`.

This is the cheapest untested lever in the whole session, and [research.md](research.md) already
flagged it as "not tested here".

---

## 7 — Process-parallel evaluation

- `nix-eval-jobs --workers N` evaluates attributes across worker processes
  `[^8]` (<https://github.com/nix-community/nix-eval-jobs>).
- `nix-fast-build` wraps it and starts builds as each attribute finishes `[^8]`.
- The session's own limit: these help **many hosts or checks**, not one toplevel. Each worker may
  re-evaluate shared dependencies.
- The Lix fork of `nix-eval-jobs` had a last visible commit in June 2024 `[^9]`.

[research.md](research.md) reached the same limit from a different angle: this repo's
`den-eval-instantiate` is many evaluations, so a list of them could use the other cores. A single
host `drvPath` cannot.

---

## 8 — The eval/build/activation split

One turn-4 row rates "measure where time goes — evaluation, build, activation" as rank 1 `[^4]`.
The supporting claim: "activation often exceeds 1.5 minutes, mostly from systemd-boot and services".
This repo never measured that split. Every number in [research.md](research.md) is evaluation only.

---

## 9 — Every claim, with its reference and its status here

Status is `unverified here` for every row. None of these ran on this repo's hardware with this repo's
config, except where the last column says otherwise.

| #   | Claim                                                                           | Ref                    | Status here                                                           |
| --- | ------------------------------------------------------------------------------- | ---------------------- | --------------------------------------------------------------------- |
| 1   | `--eval-profiler flamegraph` arrived in CppNix 2.30 (2025-07-07), absent in Lix | `[^3]` `[^11]`         | unverified here (research.md agrees from its own probe)               |
| 2   | `NIX_SHOW_STATS` / `NIX_COUNT_CALLS` work in Lix                                | `[^7]` `[^9]`          | unverified here (research.md proved it)                               |
| 3   | `nix-evaluator-stats` is a dashboard with snapshot diff                         | `[^8]` `[^10]`         | unverified here                                                       |
| 4   | Parallel eval and lazy trees are client-side, not daemon-side                   | `[^1]` `[^2]` `[^3]`   | unverified here                                                       |
| 5   | A Determinate / Nix ≥ 2.35 client against a Lix daemon is plausible             | `[^3]`                 | unverified here (research.md proved the protocol part only)           |
| 6   | Lix protocol frozen at CppNix 2.18                                              | `[^1]`                 | unverified here (research.md agrees)                                  |
| 7   | Nix 2.35 copies flake sources lazily, about 2× faster fetch/unpack              | `[^4]` `[^7]`          | unverified here                                                       |
| 8   | Lix evaluator 8–20 % faster than CppNix 2.18                                    | `[^5]`                 | unverified here                                                       |
| 9   | Lix 2.96 links mimalloc, 5–12 % wall-clock gain                                 | `[^7]`                 | unverified here                                                       |
| 10  | Lix 2.95 launches sandboxed builds up to 80 % faster                            | `[^4]`                 | unverified here                                                       |
| 11  | Lix 2.96 has experimental Cap'n'Proto local protocol                            | `[^4]`                 | unverified here                                                       |
| 12  | Lix has no parallel eval, no lazy trees, no flamegraph profiler                 | `[^11]` `[^12]` `[^5]` | unverified here (research.md agrees)                                  |
| 13  | nixpkgs eval benchmark table (2.96 dev 30.42 s … 2.34.9 33.69 s)                | `[^6]`                 | unverified here                                                       |
| 14  | `fix` is a parallel lazy evaluator with a bytecode cache                        | `[^10]`                | unverified here                                                       |
| 15  | `fix` speaks the worker protocol, `protocol=any` for Lix                        | `[^11]`                | unverified here                                                       |
| 16  | `fix -Dprof-path` gives per-body-chunk time, approximate, workers=1             | `[^2]`                 | unverified here                                                       |
| 17  | `fix --timeline` gives Perfetto spans; `--stats` gives counters                 | `[^1]`                 | unverified here                                                       |
| 18  | `fix` has a debugger with breakpoints and stepping                              | `[^1]`                 | unverified here                                                       |
| 19  | Determinate with all cores is the slowest on one NixOS config (3432 ms)         | `[^1]` `[^3]`          | unverified here                                                       |
| 20  | Nix 2.34.8 2812 ms, Lix 2.95.2 2678 ms on the same config                       | `[^1]`                 | unverified here                                                       |
| 21  | `fix` reports about 3× on real-world desktop configs                            | `[^1]` `[^15]`         | unverified here                                                       |
| 22  | Duplicate nixpkgs imports are the highest-impact config lever                   | `[^9]`                 | unverified here                                                       |
| 23  | HM as a NixOS module is a second module evaluation; 30 s to 10 s                | `[^4]`                 | unverified here                                                       |
| 24  | `useGlobalPkgs = true` avoids a second nixpkgs import                           | `[^6]`                 | unverified here                                                       |
| 25  | Flake `packages` access from a config imports nixpkgs                           | `[^6]`                 | unverified here                                                       |
| 26  | Specialisations and containers each trigger a full extra NixOS eval             | `[^4]`                 | unverified here                                                       |
| 27  | Extra binary caches are queried before the build                                | `[^4]`                 | unverified here                                                       |
| 28  | `documentation.enable = false` is a heavy hitter, no measured saving alone      | `[^5]` `[^6]`          | unverified here                                                       |
| 29  | `with lib;` forces the whole attr set                                           | `[^10]`                | unverified here                                                       |
| 30  | IFD blocks parallelism                                                          | `[^11]`                | unverified here                                                       |
| 31  | Module count is negligible against 2,700 nixpkgs modules                        | `[^6]`                 | unverified here (research.md agrees: repo code is 0.5 % of self time) |
| 32  | `GC_INITIAL_HEAP_SIZE=4G` cut wall time about 25 %, default 384 MB              | `[^9]`                 | unverified here (research.md did not test it)                         |
| 33  | A Nix commit defaults the heap to 80 % RAM capped 8 GiB                         | `[^13]`                | unverified here                                                       |
| 34  | `nix-eval-jobs` / `nix-fast-build` help many outputs, not one toplevel          | `[^8]`                 | unverified here (research.md agrees)                                  |
| 35  | Activation often exceeds 1.5 min, mostly systemd-boot and services              | `[^4]`                 | unverified here                                                       |

---

## 10 — What this means for this repo

Facts about this repo, not measurements of these claims:

- **The evaluator is one release behind the mimalloc claim.** This machine runs Lix 2.95.3. The
  session puts mimalloc in 2.96, which released 2026-10-13, before today. An upgrade is a package
  bump, not a config change. Whether nixpkgs carries 2.96 yet is untested here.
- **`anji` is a Darwin host.** Lix 2.95's "80 % faster sandbox launch" is a Linux build-phase claim,
  so it does not touch `anji`. It could touch a Linux host's _build_ time, which is outside this
  task's exit criteria.
- **The single biggest config lever the session names is already measured here.** "Duplicate nixpkgs
  imports" is the devenv overlay finding in [research.md](research.md) at 14.9 % self time. The
  session adds no new cut, only the same cause under a different name.
- **The `specialisation.llms` claim applies, and it is local.** `hosts/brys/default.nix:370` sets
  `specialisation.llms` with `inheritParentConfig = false`. The session says each specialisation
  triggers a full extra NixOS module evaluation. So the `brys` toplevel evaluates twice. No profile
  of `brys` exists yet, so the weight is unknown.
- **The activation claim is new and unmeasured.** This repo's `nixos-rebuild.sh` and the
  `darwin-rebuild` package wrap the rebuild but never split eval from build from activation. The
  session says activation can exceed 1.5 min. That is outside eval, but it would change what "make
  the update faster" means.
- **The `fix` `.drv` gate is safe on a den host and unsafe on a universal host.** [definition.md](definition.md)
  § "The `drvPath` caveat" states this. `fix`'s own "any difference from Nix is a bug" policy makes
  a `.drv` comparison the natural gate, on the den side only.
- **`GC_INITIAL_HEAP_SIZE` needs a wrapper change to reach a rebuild.** This repo wraps both
  rebuilds (`nixos-rebuild.sh`, `packages/darwin-rebuild/darwin-rebuild.sh`), so the variable can be
  set there without a system change. [research.md](research.md) measured `gc.heapSize` at 4.85 GB
  against a 384 MB start, so the claim is plausible here. It is still unmeasured.
- **Parallel evaluation is not the answer for a single host.** Both this session and
  [research.md](research.md) reach that. The `fix` benchmark makes it sharper: Determinate with all
  cores was the _slowest_ on one NixOS config.

No number in this file was measured in this repo. The next step for every avenue is in
[status.md](status.md) § "Update 2026-10-30".
