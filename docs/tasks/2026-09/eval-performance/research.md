---
type: Research
description: What this machine can profile at Nix evaluation time, one real flamegraph of a host evaluation with its top cost centres, and the protocol for a fair universal-versus-den comparison.
task: definition.md
authored_by: agent
timestamp: 2026-09-11T17:00:00+02:00
---

# Evaluation profiling — findings

Measured 2026-09-11 on `aarch64-darwin`, host `anji`. The system evaluator is **Lix 2.95.2**.
Every claim below carries the command that produces it, or a URL.

The subject of every measurement is one evaluation-only expression:

```bash
nix eval --raw '.#darwinConfigurations.anji.config.system.build.toplevel.drvPath'
```

No system build ran. Three import-from-derivation builds ran inside the first, cold evaluation;
[§ Import-from-derivation](#import-from-derivation-runs-inside-the-evaluation) explains them.

---

## Executive summary

Six findings, in order of value.

1. **Lix 2.95.2 has no flamegraph eval profiler.** CppNix 2.30 and later has one. A CppNix
   **client** profiles this repo against the Lix daemon with no system change and no lock
   rewrite. That is the working route. See [§ Part 1](#part-1--what-this-machine-can-do) and
   [§ The CppNix-client-on-Lix-daemon experiment](#the-cppnix-client-on-lix-daemon-experiment).
2. **One dependency costs about a third of the whole evaluation.**
   `nix-rosetta-builder` builds a NixOS disk image for the Linux builder VM. That forces a
   nested full `nixosSystem` evaluation plus a `closure-info`. It is **31.7 %** of the sampled
   evaluation, in one single call chain.
3. **The repo's own module code costs 0.5 % of evaluation self time.** Both module trees are a
   rounding error. The cost sits in nixpkgs `lib/modules.nix`, in `stdenv`, and in extra copies
   of nixpkgs. So neither tree can win a large amount on its own.
4. **Three nixpkgs trees evaluate in one host evaluation.** The second one, devenv's patched
   copy, alone costs **14.9 %** of evaluation self time. The `devenv` overlay on the host `pkgs`
   is the cause.
5. **Derivation instantiation, not language evaluation, is most of the wall clock in Lix.**
   `nix eval --read-only` cuts a warm run from **64.07 s to 23.35 s**, a 64 % cut, while user
   CPU time falls only from 23.72 s to 22.46 s.
6. **The CppNix client is 36 % faster and uses 30 % less memory on the same expression.**
   41.02 s against 64.07 s wall, 3.86 GB against 5.13 GB peak. The whole gap is instantiation:
   with `--read-only` the two evaluators tie at about 23 s.

---

## Part 1 — what this machine can do

### The flamegraph eval profiler: absent in Lix, present in CppNix

Lix 2.95.2 has no such flag. Two probes prove it.

```bash
nix eval --help | grep -i 'profil'                      # → no match
nix config show --json | jq -r 'keys[]' | grep -i eval
# → allow-unsafe-native-code-during-evaluation, eval-cache, eval-system, pure-eval, restrict-eval
```

A string scan of the shipped library agrees. The only profiler-shaped string is a pointer to the
old route:

```bash
strings -a /nix/store/*-lix-2.95.2/lib/liblix.dylib | grep -i 'eval-profil|flamegraph'
# → `flamegraph.pl`.        (one hit, inside the trace-function-calls documentation)
```

Upstream declined the port. Lix issue 881, "Introduce our own profiler infrastructure", is open
since 2025-06-25: <https://git.lix.systems/lix-project/lix/issues/881>. A maintainer replies
"we're definitely not porting these as is". The Lix manual holds zero hits for `eval-profiler`
(<https://docs.lix.systems/manual/lix/stable/print.html>), and a Gerrit search for
`message:eval-profiler` returns zero changes.

CppNix has the profiler since **2.30.0**, released 2025-07-08. Release notes:
<https://nix.dev/manual/nix/latest/release-notes/rl-2.30>. Feature doc:
<https://nix.dev/manual/nix/latest/advanced-topics/eval-profiler>. The pull request is
[NixOS/nix#13220](https://github.com/NixOS/nix/pull/13220), merged 2025-05-23.

Three settings, verified on the CppNix 2.35.2 binary in this machine's store:

| Setting | Default | Meaning |
|---|---|---|
| `eval-profiler` | `disabled` | `flamegraph` is the only mode |
| `eval-profile-file` | `nix.profile` | Where the profile goes |
| `eval-profiler-frequency` | `99` (Hz) | Sample rate. `0` samples after every function call |

**No experimental feature is needed.** The proof is the run itself: the command in
[§ How to run it](#how-to-run-it) works with `experimental-features = fetch-tree flakes
nix-command`, which this machine already sets.

The output is standard collapsed-stack ("folded") format: semicolon-separated frames, each
`file:line:column[:name]`, then a space and a sample count. `flamegraph.pl` reads it directly.
<https://speedscope.app/> reads it too.

### `NIX_SHOW_STATS`, `NIX_COUNT_CALLS`, `NIX_SHOW_STATS_PATH`: all three work

All three exist in Lix 2.95.2. Proof:

```bash
strings -a /nix/store/*-lix-2.95.2/lib/liblix.dylib | grep -E '^NIX_[A-Z_]+$'
# → includes NIX_SHOW_STATS, NIX_COUNT_CALLS, NIX_SHOW_STATS_PATH, NIX_SHOW_SYMBOLS
```

`NIX_SHOW_STATS=1` prints pretty JSON to **stderr**. `NIX_SHOW_STATS_PATH=<file>` sends it to a
file instead. The full field list, from a real host evaluation:

```
cpuTime
envs   { bytes, elements, number }
gc     { heapSize, totalBytes }
list   { bytes, concats, elements }
nrAvoided
nrFunctionCalls
nrLookups
nrOpUpdateValuesCopied
nrOpUpdates
nrPrimOpCalls
nrThunks
sets   { bytes, elements, number }
sizes  { Attr, Bindings, Env, Value }
symbols { bytes, number }
values { bytes, number }
```

`NIX_COUNT_CALLS=1` adds three keys:

- `primops` — an attribute set, primop name to call count.
- `functions` — an array. Each entry holds `name`, `file`, `line`, `column`, `count`.
- `attributes` — `null` in every run measured here.

So Lix **does** give per-function attribution, but by **call count only**. It never reports
self time per function. That distinction matters: a count ranks how often a function runs, not
how long it costs. The flamegraph profiler ranks time.

`NIX_SHOW_SYMBOLS=1` replaces the `symbols` summary with a flat array, so it removes the
`{ number, bytes }` pair. Do not set it unless you want the symbol table.

Documentation: <https://docs.lix.systems/manual/lix/stable/command-ref/env-common.html> covers
the first two. `NIX_SHOW_STATS_PATH` appears only in the contributors' page,
<https://docs.lix.systems/manual/lix/stable/contributing/testing.html>, marked "Undocumented".

**Overhead is near zero on wall clock.** Same warm evaluation, back to back:

| Run | Wall | User |
|---|---|---|
| Plain | 64.07 s | 23.72 s |
| `NIX_SHOW_STATS=1 NIX_COUNT_CALLS=1` | 64.12 s | 27.15 s |

Wall clock rises 0.1 %. User CPU rises 14.5 %. Always leave these two on.

### `--trace-function-calls`: present, and too large to use here

The setting exists in Lix 2.95.2.

```bash
nix config show --json | jq -r '.["trace-function-calls"].description'
```

Its own text names the conversion route: "Use the `contrib/stack-collapse.py` script distributed
with the Nix source code to convert the trace logs in to a format suitable for `flamegraph.pl`."

The output shape, one line per function entry and one per exit:

```bash
nix eval --option trace-function-calls true -vvvvv --expr '(x: y: x+y) 1 2' 2>&1 | grep function-trace
# function-trace entered «string»:1:1 at 886433161462291
# function-trace exited  «string»:1:1 at 886433161473125
```

The manual says the level is "vomit". On this build the trace appears at `-vvvvv`, not at the
default level. Note that `--vomit` is **not** a flag; `nix eval --vomit` fails with
"unrecognised flag".

**Do not use this route for a host evaluation here.** The measured `nrFunctionCalls` for `anji`
is **27,526,141**. Each call writes two lines of about 90 bytes, so the trace reaches roughly
**5 GB**. The Discourse thread that invented this route reports a 59 GB trace for a
module-heavy config: <https://discourse.nixos.org/t/nix-flamegraph-or-profiling-tool/33333>.
Disk on this machine is about 210 GB free and falling. The CppNix sampling profiler writes
21 MB for the same evaluation. Use the sampling profiler.

### Parallel evaluation: absent here, and absent upstream too

Confirmed absent in Lix:

```bash
nix config show | grep -c eval-cores     # → 0
nix config show | grep -i core           # → cores = 0   (build cores, not eval cores)
```

Confirmed absent in CppNix 2.35.2 as well:

```bash
/nix/store/*-nix-2.35.2/bin/nix config show | grep -i core   # → cores = 0
```

`eval-cores` is a **Determinate Nix** setting, not an upstream one. Its declaration lives in
`DeterminateSystems/nix-src`, `src/libexpr/include/nix/expr/eval-settings.hh`. Determinate
shipped it as a developer preview in 3.11.1 on 2025-09-05
(<https://determinate.systems/blog/changelog-determinate-nix-3111>) and raised the default core
count in 3.16.3 on 2026-03-03
(<https://determinate.systems/blog/changelog-determinate-nix-3163>). The design post is
<https://determinate.systems/blog/parallel-nix-eval> (2024-06-27). Upstream's own attempt,
[NixOS/nix#10938](https://github.com/NixOS/nix/pull/10938), closed unmerged;
[NixOS/nix#2652](https://github.com/NixOS/nix/issues/2652) stays open.

**What that means for wall clock here.** One evaluation is one thread. A bundle of N host
evaluations in one evaluator process is N times one thread. So `den-eval-instantiate` at 358 s
for 201 pairs cannot use the other cores of this machine at all.

The portable answer is process parallelism, not thread parallelism:
`nix-eval-jobs --workers <N>` (<https://github.com/nix-community/nix-eval-jobs>), which
`nix-fast-build` already wraps (<https://github.com/Mic92/nix-fast-build>). Its documented
trade-off: each worker may re-evaluate shared dependencies.

### The evaluation cache changes nothing for a deep attribute

`eval-cache = true` is the default here (`nix config show | grep eval-cache`). Disable it with
`--no-eval-cache`.

Three back-to-back warm runs of the same deep attribute:

| Run | Wall |
|---|---|
| `--no-eval-cache` | 80.03 s (first after the cold run; page cache still filling) |
| default, cache on | 65.51 s |
| default, cache on, again | 64.07 s |

The cache gives **no measurable saving**. The reason: the flake evaluation cache memoizes a
shallow flake output attribute, not a deep recursive path such as
`config.system.build.toplevel.drvPath`.

**Still pass `--no-eval-cache` for every measurement.** The cache also stores a *failure*, and
it replays that failure in under a second. That has produced fake results before, both here (see
`checks/README.md`) and upstream
(<https://discourse.nixos.org/t/profiling-optimising-nixos-configuration-derivation/75095>,
where a user reported a fake 1m30 to 25 s win that was only the cache).

### Other knobs the installed evaluator offers

| Knob | What it does | Measured effect |
|---|---|---|
| `nix eval --read-only` | Skips `.drv` instantiation | **64.07 s to 23.35 s** on the same expression |
| `nix eval --debugger` | Interactive prompt when evaluation fails | Not timed. Disables parallel evaluation where that exists |
| `max-call-depth` | Default 10000, errors above it | Not a cost knob |
| `GC_INITIAL_HEAP_SIZE` | Boehm GC start size | Not tested. `gc.heapSize` reached 4.85 GB, so a larger start may cut GC cycles |
| `NIX_SHOW_SYMBOLS` | Dumps the symbol table into the stats JSON | Removes the `symbols` summary. Avoid |

There is no heap profiler and no GC-cycle counter beyond `gc.heapSize` and `gc.totalBytes`.
Peak resident memory comes from the operating system, with `/usr/bin/time -l`.

### What upstream has and this machine does not

| Capability | Where it exists | Available here? | URL |
|---|---|---|---|
| Flamegraph eval profiler | CppNix ≥ 2.30.0 (2025-07-08) | **Yes, through a CppNix client** | <https://nix.dev/manual/nix/latest/advanced-topics/eval-profiler> |
| Derivation names inside profile frames | CppNix, PR 13261 | Yes, same route | <https://github.com/NixOS/nix/pull/13261> |
| Multi-threaded evaluation (`eval-cores`) | Determinate Nix ≥ 3.11.1 | **No** | <https://determinate.systems/blog/changelog-determinate-nix-3111> |
| `builtins.parallel` | Determinate Nix, `parallel-eval` feature | **No** | <https://determinate.systems/blog/parallel-nix-eval> |
| Lix-native profiler | Nowhere yet; declined | **No** | <https://git.lix.systems/lix-project/lix/issues/881> |
| `contrib/stack-collapse.py` | Nix and Lix source trees | Yes, but the trace is about 5 GB | <https://github.com/NixOS/nix/blob/master/contrib/stack-collapse.py> |
| Process-parallel evaluation | `nix-eval-jobs` | Yes, not yet adopted here | <https://github.com/nix-community/nix-eval-jobs> |
| Folded-stack viewer | `speedscope`, `flamelens`, `inferno` | Yes, all in nixpkgs | <https://speedscope.app/> |

---

## The CppNix-client-on-Lix-daemon experiment

**The premise holds. Evaluation runs client-side; the daemon serves the store.** A CppNix client
evaluates this repo against the Lix 2.95.2 daemon, and the flamegraph profiler works.

### The client is real CppNix, and small to fetch

```bash
nix eval --raw 'nixpkgs#nixVersions.latest.name'   # → nix-2.35.2
nix eval --raw 'nixpkgs#nix.name'                  # → nix-2.34.8
nix build --dry-run 'nixpkgs#nixVersions.latest'
# → these 4 paths will be fetched (1.51 MiB download, 4.31 MiB unpacked)
/nix/store/vq42ybar1bix8bf21nc11apl57f2igwf-nix-2.35.2/bin/nix --version
# → nix (Nix) 2.35.2
```

`nix (Nix)` is the CppNix banner; Lix prints `nix (Lix, like Nix)`. So **both**
`nixpkgs#nix` and `nixpkgs#nixVersions.latest` give a true CppNix here — the repo's nixpkgs fork
does not redirect them to Lix. Total cost: **1.51 MiB**.

### The protocol matches, and the client is trusted

```bash
/nix/store/vq42ybar1bix8bf21nc11apl57f2igwf-nix-2.35.2/bin/nix store info
# Store URL: daemon
# Version: 2.95.2
# Trusted: 1
```

A CppNix 2.35.2 client speaks to a Lix 2.95.2 daemon with no error. No protocol mismatch
appeared in any run.

### Does a pure evaluation need the daemon?

It needs it for two things, and both showed up.

- **`builtins.path` copies a source tree into the store.** That is an `addToStore` call. It is
  the single largest cost centre of this evaluation; see [§ Part 2](#part-2--the-flamegraph).
- **`.drv` instantiation writes each derivation into the store.** `--read-only` skips it and
  saves 40 s of wall clock.

`--offline` worked in every CppNix run, so no network fetch was needed once the flake inputs sat
in the store. A cold input would need the network, and `--offline` would then fail.

### The profiler works. Exact invocation

```bash
CPP=$(nix build --no-link --print-out-paths 'nixpkgs#nixVersions.latest' | grep -v -- -man | head -1)

"$CPP/bin/nix" eval \
  --no-write-lock-file --no-update-lock-file --offline \
  --option eval-profiler flamegraph \
  --option eval-profile-file /path/to/out.folded \
  --raw '.#darwinConfigurations.anji.config.system.build.toplevel.drvPath'
```

### The lock-write hazard: guarded, and it never fired

Every CppNix run carried `--no-write-lock-file --no-update-lock-file --offline`. Hashes were
recorded before the first run and checked after every batch.

```bash
shasum -a 256 flake.lock devenv.lock
# be98a0374ce5ffb716bcc230b2fbd891ddeadb8a6e86585382f50234260eb49e  flake.lock
# 460835cedbe8997ba75c46d5f5e5774b45eed6d7355c5c2eaee9f1c71f6358f9  devenv.lock
```

**Both hashes were identical before and after all nine CppNix invocations.** No lock file was
written. No restore was needed.

### One real hazard did fire: a dirty tree that changes mid-evaluation

Two profiler runs against the live working copy failed part way:

```
error: store path ('/nix/store/kk5a00n1s49wk2cvl7b06xsj9cdjn8xk-source') was hashed to avoid a
full copy at first, but upon reading it again, the contents have changed
('/nix/store/w97w04icgylgfbld2i2lw9q0p6c68h39-source'), so we can not proceed.
Make sure files do not change during evaluation
```

Another agent was editing tracked files while the evaluation ran. A dirty `git+file:` tree gets
hashed twice, and the two hashes disagreed. The profile file was still written, but it covered
only about 73 % of the run.

**The fix: profile a fixed revision, never the live dirty tree.**

```bash
REV=$(jj --config signing.behavior=drop log -r '@' --no-graph -T 'commit_id')
"$CPP/bin/nix" eval ... --raw "git+file://$PWD?rev=$REV#darwinConfigurations.anji...drvPath"
```

Every fixed-revision run completed, and two of them returned the **same** `drvPath`. Live-tree
runs returned a different `drvPath` each time, because the tree kept changing.

### Overhead of the profiler

Same fixed revision, back to back:

| Run | Wall | User | Sys | Peak RSS |
|---|---|---|---|---|
| CppNix, plain | 41.02 s | 21.01 s | 7.65 s | 3.86 GB |
| CppNix, `eval-profiler flamegraph` @ 99 Hz | 50.27 s | 22.92 s | 9.07 s | 3.91 GB |
| CppNix, `--read-only`, plain | 23.20 s | 19.42 s | 5.88 s | 3.91 GB |
| CppNix, `--read-only` + profiler @ 99 Hz | 25.05 s | 20.73 s | 6.28 s | 3.91 GB |

Profiler overhead: **+22.5 % wall** and **+9.1 % user** on the full run, **+8.0 % wall** on the
read-only run. A 999 Hz run wrote a 184 MB profile against 33 MB at 99 Hz. **Keep 99 Hz.**

### Is this a recommended workflow, or a one-off trick?

**A recommended workflow for measurement. Never for activation.**

Reasons to adopt it:

- It costs 1.51 MiB and touches no system configuration.
- The store protocol matches, and the client is trusted.
- It gave the answer that the system evaluator cannot give at all.
- It also gave a second, unasked answer: CppNix is 36 % faster on this expression.

Reasons to keep it narrow:

- **The profile describes CppNix, not Lix.** The two evaluators share an ancestor at Nix 2.18
  (<https://lix.systems/about/>) and have diverged since. A cost share measured on CppNix
  transfers to Lix only when the cost is in **Nix code**, not in evaluator internals.
- The main finding of this spike survives that limit, because it is Nix code: the
  `nix-rosetta-builder` disk-image chain runs in both evaluators. `nrFunctionCalls` is
  27,526,141 in Lix, and Lix agrees with the flamegraph that `lib/modules.nix` is the top file by
  call count. Both evaluators reach about 23 s of pure evaluation with `--read-only`.
- A **relative** conclusion transfers well. An **absolute** second count does not. State which
  evaluator produced each number.
- A second Nix in the store is one more thing to keep current. Pin it by nixpkgs attribute, not
  by store path.
- **Never activate a system with the CppNix client**, and never let it write a lock file.
  Measurement only.

---

## Part 2 — the flamegraph

### The artifacts

| File | Contents |
|---|---|
| `anji-eval-flamegraph-fixedrev-99hz.svg` | Full evaluation, with instantiation. 3570 samples |
| `anji-eval-flamegraph-readonly-99hz.svg` | `--read-only`, pure evaluation. 2341 samples |
| `anji-eval-flamegraph-99hz.svg` | Live dirty tree, partial run. Keep for comparison only |
| `raw/*.folded` | The raw collapsed stacks that produced each SVG |
| `raw/anji-stats-*.json` | `NIX_SHOW_STATS` plus `NIX_COUNT_CALLS` output |

3570 samples at 99 Hz is 36.1 s of sampled evaluation inside a 50.27 s run. The 14 s difference
is time the sampler could not attribute, mostly store input and output.

### The timing table

Every row is one warm run of the same expression on this machine.

| # | Evaluator | Flags | Wall | User | Sys | Peak RSS |
|---|---|---|---|---|---|---|
| 1 | Lix 2.95.2 | cold, first of the day, `--no-eval-cache` | 243.67 s | 28.94 s | 9.34 s | 5.57 GB |
| 2 | Lix 2.95.2 | `--no-eval-cache` | 80.03 s | 24.14 s | 8.21 s | 5.50 GB |
| 3 | Lix 2.95.2 | default (cache on) | 64.07 s | 23.72 s | 8.60 s | 5.13 GB |
| 4 | Lix 2.95.2 | `--no-eval-cache` + stats | 64.12 s | 27.15 s | 8.71 s | 5.57 GB |
| 5 | Lix 2.95.2 | `--read-only --no-eval-cache` + stats | 23.35 s | 22.46 s | 6.25 s | 5.56 GB |
| 6 | CppNix 2.35.2 | fixed revision, plain | 41.02 s | 21.01 s | 7.65 s | 3.86 GB |
| 7 | CppNix 2.35.2 | fixed revision, `--read-only` | 23.20 s | 19.42 s | 5.88 s | 3.91 GB |

Read three things out of it.

- **Cold against warm is 3.8x.** Row 1 against row 3. Never quote a cold number as a baseline.
- **Instantiation dominates the Lix wall clock.** Row 3 against row 5: 40.7 s of wall clock
  disappears, and only 3.6 s of CPU time with it. Lix writes each `.drv` through the daemon and
  waits.
- **The two evaluators tie on pure evaluation.** Row 5 against row 7: 23.35 s against 23.20 s.
  The whole CppNix advantage in row 6 is cheaper instantiation, 17.8 s against 40.7 s.

### Top cost centres by name and share

Self time, from the complete fixed-revision profile, 3570 samples.

| Share | Cost centre |
|---|---|
| **31.3 %** | `nixpkgs/lib/sources.nix:61:5` — `cleanSourceFilter` |
| 7.3 % | `nixpkgs/pkgs/stdenv/generic/make-derivation.nix:970:24` — `makeCMakeFlags` |
| 5.1 % | `nixpkgs/pkgs/stdenv/generic/make-derivation.nix:983:18` |
| 3.4 % | devenv's nixpkgs, `pkgs/build-support/rust/build-rust-crate/default.nix:52:14` |
| 2.4 % | devenv's nixpkgs, `lib/lists.nix:1956:20` |
| 1.7 % | `nixpkgs/lib/trivial.nix:1109:86` — `primop functionArgs` |
| 1.4 % | `nixpkgs/lib/modules.nix:707:56` — `applyModuleArgs` |
| 1.2 % | `nixpkgs/pkgs/stdenv/generic/make-derivation.nix:971:24` — `makeMesonFlags` |
| 1.2 % | `nixpkgs/pkgs/development/interpreters/python/mk-python-derivation.nix:407:9` |

Grouped by file:

| Share | File |
|---|---|
| **31.7 %** | `nixpkgs/lib/sources.nix` |
| **20.4 %** | `nixpkgs/pkgs/stdenv/generic/make-derivation.nix` |
| 4.9 % | `nixpkgs/lib/modules.nix` |
| 4.5 % | devenv nixpkgs, `pkgs/build-support/rust/build-rust-crate/default.nix` |
| 2.8 % | devenv nixpkgs, `lib/lists.nix` |
| 2.1 % | devenv nixpkgs, `pkgs/stdenv/generic/make-derivation.nix` |
| 2.0 % | `nixpkgs/pkgs/development/interpreters/python/mk-python-derivation.nix` |
| 1.9 % | `nixpkgs/pkgs/development/haskell-modules/generic-builder.nix` |

`lib/modules.nix` is only 4.9 % of **self** time, but it is **99.96 %** of *inclusive* time. That
is expected: every module evaluation passes through it.

### Grouped by source tree — the decisive table

Self time per source root, both profiles:

| Source root | Full run | `--read-only` |
|---|---|---|
| the repo's nixpkgs fork | 79.69 % | 77.87 % |
| **devenv's patched nixpkgs (second copy)** | **14.76 %** | **14.91 %** |
| upstream nixpkgs (third copy) | 1.74 % | 1.88 % |
| the devenv flake itself | 1.12 % | 1.03 % |
| primops with no source position | 1.09 % | 2.05 % |
| Nix internals | 0.36 % | 0.56 % |
| home-manager | 0.28 % | 0.13 % |
| **`nix-configs` — this repo's own code** | **0.25 %** | **0.51 %** |
| nix-darwin | below 0.2 % | 0.17 % |
| stylix | 0.06 % | 0.13 % |

**Read this carefully.** The repo's own 194-file universal tree plus its 105-file den tree
account for **0.5 %** of evaluation self time. The extra nixpkgs copies account for **16.8 %**.

### The single biggest cost: the rosetta-builder disk image

One call chain carries **1133 of 3570 samples, 31.7 %**, in the full profile, and **730 of 2341,
31.2 %**, in the read-only profile:

```
«cpick/nix-rosetta-builder»/module.nix:213:25
  → lib/attrsets.nix:1729:13 primop head
    → lib/customisation.nix:101:24 primop seq
      → derivationStrict: nixos-disk-image
        → derivationStrict: closure-info
          → derivationStrict: nixos-26.11.20260908.d6524aa
            → lib/sources.nix:452:17 primop path
              → lib/sources.nix:61:5 cleanSourceFilter
```

Read it bottom-up. `nix-rosetta-builder` interpolates the disk-image derivation into a VM
configuration. That forces a **nested, complete `nixosSystem` evaluation** for the Linux builder
guest, plus a `closure-info` over its whole closure, plus a `builtins.path` that walks a source
tree through `cleanSourceFilter`.

`module.nix:213` is the interpolation:

```nix
location = "${imageWithFinalConfig}/${imageWithFinalConfig.passthru.filePath}";
```

The repo turns it on at `hosts/anji/default.nix:32`:

```nix
kdn.darwin.rosetta-builder.enable = true;
```

The cost survives `--read-only`, so it is genuine evaluator work, not only a store copy.

### The second biggest: the devenv overlay on a host `pkgs`

`flake.nix:207` puts `inputs.devenv.overlays.default` into `flake.overlays.default`, and every
host takes that overlay. Two consequences appear in the profile.

1. devenv pins **its own patched nixpkgs**. That second nixpkgs carries 14.9 % of self time,
   14.76 % in the full run. The unpatched source it patches appears as a **third** nixpkgs at
   1.9 %.
2. devenv is a Rust program built through a generated `Cargo.nix` of about 39,000 lines. The
   profile shows `build-rust-crate` at 4.5 % self time, and `Cargo.nix` itself at 1.1 %. Under
   `NIX_COUNT_CALLS`, `Cargo.nix` alone takes **2,159,370** of 27,526,141 function calls, which
   is **7.8 %**.

The chain that pulls it in is visible:

```
derivationStrict: system-applications
  → derivationStrict: devenv-wrapped-2.3.1
    → derivationStrict: rust_devenv-run-tests-2.3.1
```

So `devenv` reaches a host `pkgs` through `environment.systemPackages` or an equivalent, and the
whole Rust crate graph evaluates with it.

### Cross-check: `NIX_COUNT_CALLS` agrees

The Lix counters, from the same expression, rank source trees the same way.

| Function calls | Share | Source root |
|---|---|---|
| 19,947,837 | 72.5 % | the repo's nixpkgs fork |
| 4,711,753 | 17.1 % | devenv's patched nixpkgs |
| 2,162,934 | 7.9 % | the devenv flake (`Cargo.nix`) |
| 268,502 | 1.0 % | upstream nixpkgs, third copy |
| 106,685 | 0.4 % | home-manager |
| 21,558 | **0.08 %** | this repo |

Top file by call count is `lib/modules.nix` at 7,000,932 calls, 25.4 % of all calls. That
matches the flamegraph's 99.96 % inclusive share.

Two counters worth watching over time:

- `nrOpUpdateValuesCopied = 204,791,556`. The `//` operator copied 204 million values. Upstream
  names list and attribute-set copying as the module system's main linear cost:
  [NixOS/nixpkgs#152046](https://github.com/NixOS/nixpkgs/pull/152046).
- `sets.bytes = 4,157,072,560`. 4.16 GB of attribute sets, against `gc.heapSize` of 4.85 GB.

**The two mechanisms agree on the ranking, and they disagree on the reason.** The counters put
`lib/modules.nix` first by call count. The sampling profiler puts `lib/sources.nix` first by
time. Both are true: `modules.nix` runs a huge number of very cheap calls, and
`cleanSourceFilter` runs fewer, far more expensive ones. **Never rank cost by call count alone.**

### Import-from-derivation runs inside the evaluation

The cold run built three things *during* evaluation:

```
building '/nix/store/...-devenv-nixpkgs-patched.drv'
building '/nix/store/...-cabal2nix-cachix-api.drv'
building '/nix/store/...-cabal2nix-hnix-store-nar.drv'
building '/nix/store/...-kdn-authorized-keys.drv'
```

That is import-from-derivation. It serializes evaluation behind a build, and it explains most of
the 243.67 s cold figure against 64.07 s warm. `devenv-nixpkgs-patched` alone reported
"installPhase completed in 1 minutes 12 seconds".

An IFD is invisible in a warm run, because the outputs already sit in the store. It hits every
fresh machine, every CI runner and every garbage-collected store.

### What each mechanism reveals, and what it cannot

| Mechanism | It reveals | It cannot |
|---|---|---|
| `/usr/bin/time -l` | Wall, user, sys, peak RSS, page faults | Anything about where the time goes |
| `NIX_SHOW_STATS=1` | `cpuTime`, thunks, allocations, GC heap, `//` copies | Attribute any of it to a function |
| `NIX_COUNT_CALLS=1` | Per-function **call counts** with `file:line:column`, per-primop counts | Report **time**. A cheap hot function outranks an expensive one |
| CppNix `eval-profiler flamegraph` | Per-frame **self and inclusive time**, full call stacks, derivation names | Run on Lix. Describe Lix internals |
| `--trace-function-calls` | Every entry and exit with a timestamp | Fit on disk here (about 5 GB) |
| `nix eval --read-only` | Splits pure evaluation from `.drv` instantiation | Produce a `.drv` you can build |
| CppNix against Lix, same expression | Which evaluator costs less on this workload | Prove a Nix-code cost share for Lix |
| `nix build --dry-run` | Download size before a fetch | Anything about evaluation |

### How to run it

No context needed. Copy and paste.

```bash
cd ~/dev/github.com/nazarewk-iac/nix-configs

# 0. Guard the lock files. Record the hashes, and check them again at the end.
shasum -a 256 flake.lock devenv.lock

# 1. Get the CppNix client and the renderer. About 1.6 MiB together.
CPP=$(nix build --no-link --print-out-paths 'nixpkgs#nixVersions.latest' | grep -v -- '-man' | head -1)
FG=$(nix build --no-link --print-out-paths 'nixpkgs#flamegraph')

# 2. Pin a revision. A dirty tree makes the evaluation fail part way.
REV=$(jj --config signing.behavior=drop log -r '@' --no-graph -T 'commit_id')

# 3. Profile. Keep 99 Hz; 999 Hz writes 184 MB and adds no detail.
OUT=/tmp/anji-eval
"$CPP/bin/nix" eval \
  --no-write-lock-file --no-update-lock-file --offline \
  --option eval-profiler flamegraph \
  --option eval-profile-file "$OUT.folded" \
  --raw "git+file://$PWD?rev=$REV#darwinConfigurations.anji.config.system.build.toplevel.drvPath"

# 4. Render.
"$FG/bin/flamegraph.pl" --countname samples --width 1800 "$OUT.folded" > "$OUT.svg"
open "$OUT.svg"

# 5. Cross-check with the Lix counters on the same expression.
NIX_SHOW_STATS=1 NIX_COUNT_CALLS=1 NIX_SHOW_STATS_PATH="$OUT.stats.json" \
  nix eval --no-eval-cache --raw '.#darwinConfigurations.anji.config.system.build.toplevel.drvPath'
jq 'del(.functions,.primops,.attributes)' "$OUT.stats.json"

# 6. Split pure evaluation from instantiation.
/usr/bin/time -l nix eval --read-only --no-eval-cache --raw \
  '.#darwinConfigurations.anji.config.system.build.toplevel.drvPath'

# 7. Check the guard again. Both hashes must match step 0.
shasum -a 256 flake.lock devenv.lock
```

Rank the cost centres from a folded file with the two helper scripts kept beside the artifacts
(`analyze_folded.py`, `callers.py`). Or drop the `.folded` file into
<https://speedscope.app/>, open the Sandwich View, and filter on `derivationStrict`.

For a NixOS host, replace the attribute path:

```bash
'.#nixosConfigurations.brys.config.system.build.toplevel.drvPath'
```

For a den host, use `denConfigurations`:

```bash
'.#denConfigurations.<name>.config.system.build.toplevel.drvPath'
```

---

## Part 3 — the universal-versus-den comparison

**Do not run this yet.** The two trees are not at feature parity. A run today compares a
complete tree against an incomplete one, and the incomplete one wins for the wrong reason.

This section is the protocol to run once parity arrives.

### Hold these constant

| Thing | How |
|---|---|
| Host | One host, evaluated both ways. Never compare host A on one tree to host B on the other |
| Machine | One machine, one architecture. No cross-machine number |
| Load | No other build, no other agent, no concurrent evaluation. Check with `uptime` before each batch |
| nixpkgs revision | The same `flake.lock`. Never compare across a flake update |
| Evaluator | One binary for the whole batch. State which one in every result |
| Store warmth | Warm. Run one discard run first. Never quote a cold run |
| Cache state | `--no-eval-cache` on every run |
| Tree state | A **fixed revision** through `git+file://$PWD?rev=<REV>`. Never the live tree |
| Instantiation | Both `--read-only` and plain, as two separate series |
| Option surface | The same set of enabled features. See [§ The parity confound](#the-parity-confound) |

### Measure these

| Metric | Source | Why |
|---|---|---|
| Wall clock | `/usr/bin/time -l` | The number a person feels |
| User CPU | `/usr/bin/time -l` | Language work, free of daemon wait |
| System CPU | `/usr/bin/time -l` | Store and syscall work |
| Peak RSS | `/usr/bin/time -l` | 5.13 GB today. A regression here breaks small machines |
| `cpuTime` | `NIX_SHOW_STATS` | The evaluator's own view, less noisy than wall clock |
| `nrFunctionCalls` | `NIX_SHOW_STATS` | Deterministic. Identical inputs give an identical count |
| `nrThunks`, `nrAvoided` | `NIX_SHOW_STATS` | Laziness. A rise in `nrThunks` with no rise in `nrAvoided` means new strict work |
| `nrOpUpdateValuesCopied` | `NIX_SHOW_STATS` | Merge cost. 204 M today |
| `sets.bytes`, `gc.heapSize` | `NIX_SHOW_STATS` | Allocation pressure |
| Self-time shares | CppNix flamegraph | Which tree's own code costs what |

**The deterministic counters are the primary evidence, not the clock.** `nrFunctionCalls`,
`nrThunks` and `nrOpUpdateValuesCopied` repeat exactly for identical inputs — this spike measured
27,526,141 function calls in three separate runs. Wall clock varied by 25 % over the same runs.

### Repeats

- **1 discard run** to warm the page cache. Throw it away. Row 2 of the timing table above is
  16 s slower than row 3 for exactly this reason.
- **5 measured runs** per configuration, interleaved A-B-A-B-A-B, not five A then five B. An
  interleave defends against slow machine drift, such as thermal throttling or a background
  build.
- **Report the median and the range**, not the mean. One outlier from a background job pulls a
  mean badly.
- The counters need only **1 run** each, because they are deterministic. Run a second to confirm
  it, then stop.

nixpkgs CI uses this exact shape: counters from `NIX_SHOW_STATS` plus a paired t-test, in
`ci/eval/compare/cmp-stats.py`. Use `hyperfine --warmup 1 --runs 5` for the clock part; Lix's own
`bench/bench.py` does.

### What a valid conclusion needs

All five, or the conclusion is void:

1. **The two configurations produce the same behaviour.** Compare a list of evaluated option
   values, or compare the built closure. See [§ The drvPath trap](#the-drvpath-trap).
2. **The counters move in the same direction as the clock.** A wall-clock win with no counter
   win is machine noise, not a real win.
3. **The self-time share of each tree's own code is stated.** It is 0.5 % today. A tree cannot
   win more than it spends.
4. **The confound test passes.** See the next section.
5. **The evaluator is named.** A CppNix number and a Lix number are not comparable.

### The parity confound

**The naive run compares work, not efficiency.** The den tree carries 105 aspect files; the
universal tree carries 194 modules plus 3 meta files. If den simply implements less, it
evaluates less, and it "wins" while doing nothing better.

Detect it, do not assume it away. Three tests:

1. **Count the evaluated option surface, not the files.** Evaluate
   `builtins.length (builtins.attrNames config)` at several levels, and count the leaf options
   both trees declare. A tree with fewer declared options is doing less work.
2. **Diff the evaluated value set.** Build a flat map of every `config.*` leaf, both trees, and
   diff the key sets. Every key that only one tree has is unmatched work. Report the count.
   Normalise the comparison to the intersection, and report the difference separately.
3. **Normalise by work.** Report **`cpuTime` per 1000 evaluated leaf options**, next to the raw
   `cpuTime`. A tree that is genuinely more efficient wins on the normalised figure too. A tree
   that only does less wins on the raw figure and loses or ties on the normalised one.

Report all three. Never publish a raw second count on its own.

Two more confounds to name:

- **The nixpkgs instance count.** Whichever tree pulls one nixpkgs instead of three starts with a
  16.8 % head start that has nothing to do with the module system. Count the distinct nixpkgs
  store roots in each profile, exactly as this spike did.
- **The nested-evaluation count.** `modules/meta/default.nix:28` runs a nested `lib.evalModules`
  in `mkSubmodule`, and `nix-rosetta-builder` runs a nested `nixosSystem`. Count each nested
  evaluation per tree before you compare anything.

### The `drvPath` trap

**A `drvPath` equality proof is invalid for the universal tree.** `modules/meta/default.nix:96`
declares `options.self`, and `flake.nix:207` puts `kdnConfig = self.kdnMetaModule.config` into
the overlay. So `self` reaches the evaluated config, and any edit anywhere in the repo changes
every host's `drvPath`. This spike observed it directly: four live-tree runs returned four
different `drvPath` values while another agent edited unrelated files.

`denConfigurations` never reads `self`, so a den-side `drvPath` comparison **is** valid. That is
the single exception.

For the universal tree, prove sameness with an option-value comparison or a closure comparison:

```bash
# Option values: dump a flat map of evaluated leaves and diff it.
nix eval --json '.#darwinConfigurations.anji.config.environment.systemPackages' \
  --apply 'map (p: p.name or "?")' | jq -S . > /tmp/a.json

# Closure: build both and diff the derivations.
nix run 'nixpkgs#nix-diff' -- /tmp/a.drv /tmp/b.drv
```

---

## Levers already visible in this repo's code

Named, with a `file:line` and an estimated weight. **Nothing was changed.**

| Weight | Where | What it is |
|---|---|---|
| **about 31 %** | `hosts/anji/default.nix:32` — `kdn.darwin.rosetta-builder.enable = true` | Pulls `nix-rosetta-builder`, whose `module.nix:213` interpolates a `nixos-disk-image`. That forces a nested full `nixosSystem` evaluation plus a `closure-info`. Measured 1133 of 3570 samples. **Look for a lazier way to reference the image, or gate it behind an option that a plain build does not touch.** |
| **about 17 %** | `flake.nix:207` — `inputs.devenv.overlays.default` in `flake.overlays.default` | Adds devenv's own patched nixpkgs as a second full nixpkgs instance, 14.9 % of self time, and the unpatched source as a third, 1.9 %. **A host does not need devenv. Move that overlay to the devenv shell only.** |
| **about 8 %** | the same overlay, through `system-applications` → `devenv-wrapped-2.3.1` | devenv's generated `Cargo.nix` is about 39,000 lines and takes 2,162,934 of 27,526,141 function calls. It evaluates because `devenv` reaches a host package list. |
| unmeasured, likely large on NixOS | `modules/universal/default.nix:96` — `home-manager.useGlobalPkgs = false` | Each Home Manager user imports its own nixpkgs instance. `nixos/modules/misc/nixpkgs.nix` states that sharing one instance exists "to increase the performance of evaluation". home-manager is only 0.28 % of self time on `anji`, which has few users, so measure a NixOS host before you act. |
| unmeasured, expect a few percent | `modules/universal/default.nix:207-210` — `documentation.nixos.enable = true` and the man-db cache | The famous "39 % of evaluation" figure ([nixpkgs#83871](https://github.com/NixOS/nixpkgs/pull/83871)) is stale. The docs split in [nixpkgs#149532](https://github.com/NixOS/nixpkgs/pull/149532) cut it to about 4 %. NixOS hosts only, so it does not touch `anji`. Measure before you turn it off. |
| about 5 % of self time, 25 % of calls | `modules/meta/default.nix:28` — `mkSubmodule` runs a nested `lib.evalModules` | It also passes `builtins.removeAttrs config [...]` **into** the child at priority 1100, so the whole parent `config` must evaluate and then merge into the child. Called at `flake.nix:293`, `flake.nix:423`, `flake.nix:507`, `flake.nix:533`, `modules/universal/default.nix:94`, `hosts/anji/default.nix:213`. Upstream calls a data-only submodule fixpoint avoidable: [nixpkgs#257511](https://github.com/NixOS/nixpkgs/pull/257511). |
| **near zero** | `modules/meta/default.nix:15` — `lib.filesystem.listFilesRecursive` | The recursive loader scan itself. Upstream measured `listFilesRecursive` over all ~85,000 nixpkgs files at **708.6 ms to 665.2 ms** total: [nixpkgs#449744](https://github.com/NixOS/nixpkgs/pull/449744). 194 files cost microseconds. **Do not optimise the scan.** The cost is the fan-out of what it imports, not the read. |
| **near zero** | `modules/den/flake-module.nix:58` — `builtins.readDir ../../hosts-den` | The same reasoning. It reads one directory. |
| **near zero** | the many `builtins.readFile` calls in `modules/den/aspects/*.nix` | Each reads one small shell script. `modules/den/aspects/jj-fork.nix:95`, `nix.nix:81`, `zellij.nix:82`, and about twenty more. Not a cost. |
| cold runs only, but large | three IFD builds during a cold evaluation | `devenv-nixpkgs-patched`, `cabal2nix-cachix-api`, `cabal2nix-hnix-store-nar`, plus `kdn-authorized-keys` at `modules/universal/profile/user/kdn/default.nix:99`. They turn 64 s into 244 s on a fresh store. Remove the devenv overlay and the first one goes away. |

### The wall-clock gap is instantiation, and it is the cheapest win

`--read-only` cuts a Lix run from 64.07 s to 23.35 s while user CPU falls only 1.3 s. So Lix
spends about 40 s writing `.drv` files through the daemon and waiting for it. CppNix spends
about 18 s on the same work.

Three routes, in rising order of effort:

1. Use `--read-only` for every evaluation that does not need a `.drv`. A check that only asserts
   an option value never needs one.
2. Use a CppNix client for a bulk instantiation such as `den-eval-instantiate`. Measured 36 %
   faster with no repo change.
3. Use `nix-eval-jobs --workers N` for a bundle of many host evaluations. Neither evaluator here
   has `eval-cores`, so process parallelism is the only way to reach the other cores.

---

## Claims this spike could not verify

- **The Lix issue 881 quote is single-sourced.** `git.lix.systems` sits behind bot protection and
  a re-fetch returned 403. The conclusion is safe, because the Gerrit search and the manual grep
  are independent and both returned zero.
- **No Lix document states a blanket "we do not track upstream features" policy.** The evidence
  is a divergence list at <https://lix.systems/about/> plus per-feature refusals. The formal
  freeze page freezes Flakes only.
- **`GC_INITIAL_HEAP_SIZE` was not tested.** `gc.heapSize` reached 4.85 GB, so a larger initial
  heap may cut GC cycles. Unmeasured here.
- **No NixOS host was profiled.** Every number is from `anji`, a Darwin host. The `documentation`
  and `useGlobalPkgs` levers are NixOS-only and therefore unmeasured.
- **The `useGlobalPkgs = false` weight is unmeasured.** Upstream has no
  one-instance-versus-two benchmark either.
- **The `--trace-function-calls` trace size is an estimate**, from `nrFunctionCalls` times two
  lines of about 90 bytes. No full trace was written, by design.
- **The 999 Hz profile was discarded.** Both 999 Hz runs hit the dirty-tree error, and the 184 MB
  file was deleted to save disk. The 99 Hz result at a fixed revision is the clean one.
- **`nix eval --read-only` returned a different `drvPath` from a plain run.** Every live-tree run
  did, because the tree changed between runs. So this spike **did not** prove that `--read-only`
  computes the same `drvPath` as a plain run. Confirm that on a quiet tree before you rely on it.
- **No cross-evaluator equality check ran.** CppNix and Lix returned different `drvPath` values,
  but again on a changing tree. Whether the two evaluators agree on a `drvPath` for identical
  input is untested here.

---

## Sources

Every upstream claim, with its URL.

| Claim | URL |
|---|---|
| CppNix eval profiler feature doc | <https://nix.dev/manual/nix/latest/advanced-topics/eval-profiler> |
| Nix 2.30.0 release notes, profiler paragraph | <https://nix.dev/manual/nix/latest/release-notes/rl-2.30> |
| Nix 2.30.0 announcement, 2025-07-08 | <https://discourse.nixos.org/t/nix-2-30-0-released/66449> |
| The profiler pull request | <https://github.com/NixOS/nix/pull/13220> |
| Derivation names in frames | <https://github.com/NixOS/nix/pull/13261> |
| Lix declines the port, issue 881 | <https://git.lix.systems/lix-project/lix/issues/881> |
| Lix manual, single page (zero profiler hits) | <https://docs.lix.systems/manual/lix/stable/print.html> |
| Lix `NIX_SHOW_STATS` and `NIX_COUNT_CALLS` docs | <https://docs.lix.systems/manual/lix/stable/command-ref/env-common.html> |
| Lix `NIX_SHOW_STATS_PATH`, contributors' page | <https://docs.lix.systems/manual/lix/stable/contributing/testing.html> |
| Lix diverged at Nix 2.18 | <https://lix.systems/about/> |
| `eval-cores` in Determinate Nix 3.11.1 | <https://determinate.systems/blog/changelog-determinate-nix-3111> |
| `eval-cores` default raised, 3.16.3 | <https://determinate.systems/blog/changelog-determinate-nix-3163> |
| Parallel evaluation design post | <https://determinate.systems/blog/parallel-nix-eval> |
| Upstream multithreaded evaluator, closed unmerged | <https://github.com/NixOS/nix/pull/10938> |
| Upstream parallel evaluation issue, open | <https://github.com/NixOS/nix/issues/2652> |
| `contrib/stack-collapse.py` | <https://github.com/NixOS/nix/blob/master/contrib/stack-collapse.py> |
| The trace-to-flamegraph route, and the 59 GB trace | <https://discourse.nixos.org/t/nix-flamegraph-or-profiling-tool/33333> |
| FlameGraph, upstream | <https://github.com/brendangregg/FlameGraph> |
| speedscope | <https://speedscope.app/> |
| `nix-eval-jobs` | <https://github.com/nix-community/nix-eval-jobs> |
| `nix-fast-build` | <https://github.com/Mic92/nix-fast-build> |
| NixOS rebuild slowness, tracking issue | <https://github.com/NixOS/nixpkgs/issues/57477> |
| Evaluation times over the years | <https://discourse.nixos.org/t/a-look-at-nixos-nixpkgs-evaluation-times-over-the-years/65114> |
| A modern end-to-end profiling walk-through | <https://discourse.nixos.org/t/profiling-optimising-nixos-configuration-derivation/75095> |
| Module `imports` fan-out proof of concept, 4.0 s to 1.4 s | <https://github.com/NixOS/nixpkgs/issues/137168> |
| Minimal modules, RFC 22 | <https://github.com/NixOS/rfcs/pull/22> |
| List concatenation is O(n) in the merge machinery | <https://github.com/NixOS/nixpkgs/pull/152046> |
| Module system speed-up, merged 2026-09-09 | <https://github.com/NixOS/nixpkgs/pull/517881> |
| Submodule fixpoint is avoidable for data | <https://github.com/NixOS/nixpkgs/pull/257511> |
| `documentation.nixos.enable` at 39 %, stale | <https://github.com/NixOS/nixpkgs/pull/83871> |
| The docs split that made it stale | <https://github.com/NixOS/nixpkgs/pull/149532> |
| `listFilesRecursive` costs milliseconds | <https://github.com/NixOS/nixpkgs/pull/449744> |
| NixOS wiki, evaluation performance | <https://wiki.nixos.org/wiki/Nix_Evaluation_Performance> |
