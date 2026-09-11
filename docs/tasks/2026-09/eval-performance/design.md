---
type: Design
description: The design of a repeatable evaluation-profile harness, the parity-gated tree comparison, and the one identified check-speed lever, each with an acceptance number.
task: definition.md
authored_by: agent
timestamp: 2026-09-11T22:00:00+02:00
---

# Evaluation performance — design

[research.md](research.md) measured where evaluation time goes. This design turns that measurement
into three things that land and repeat.

**Read the evaluator limit first.** `eval-cores` is a Determinate Nix setting. Lix 2.95.2 does not
have it, and CppNix 2.35.2 does not have it either (research.md § "Parallel evaluation"). So one
evaluation is one thread. A shard of one check into several derivations gives **zero** wall-clock
win for a single `nix build`, because that one client process evaluates every member. Process
parallelism is the only route to the other cores, and this design does not take it.

---

## 1 — the measurement harness

Three committed files:

| File | Job |
|---|---|
| `hack/eval-profile.sh` | Profile one attribute end to end |
| `hack/eval-profile-rank.py` | Rank one folded-stack file by self time |
| `hack/eval-compare.sh` | The A/B protocol of § 2 |

`hack/` already holds nine shell helpers and one plain Python helper, so both file kinds match the
convention. `.gitignore` allowlists `!*.sh` and `!*.py`.

```bash
hack/eval-profile.sh                                     # host anji, the default attribute
hack/eval-profile.sh '.#nixosConfigurations.brys.config.system.build.toplevel.drvPath'
KDN_EVAL_READ_ONLY=1 hack/eval-profile.sh                # pure evaluation, no instantiation
```

The script fetches a CppNix client, because Lix ships no flamegraph profiler and CppNix has one
since 2.30.0. It costs about 1.5 MiB, it changes no system configuration, and it profiles against
the Lix daemon with no protocol error (research.md § "The CppNix-client-on-Lix-daemon experiment").

### It guards four hazards

| Guard | The hazard it answers |
|---|---|
| `--no-write-lock-file --no-update-lock-file --offline`, plus a shasum of both lock files before and after | A silent lock rewrite. It never fired across nine CppNix runs, and it stays because the failure is unrecoverable in a fork repository |
| One pinned revision through `git+file://$PWD?rev=<REV>` | A dirty tree that changes mid-run. Two earlier profiler runs failed part way with "the contents have changed" |
| `--no-eval-cache` on every call | A replayed failure. `den-eval-instantiate` failed in 58 s and then replayed that failure in 0.6 s ([../../../../checks/README.md](../../../../checks/README.md)) |
| A one-minute load ceiling, with a `KDN_EVAL_FORCE=1` escape | A loaded machine. This design was itself written while a `nix build` blocked every timing |

### The output stays ephemeral

Everything lands under `.cache/eval-profile/<UTC stamp>/`, and `.gitignore` ignores `/.cache/`.
Three reasons:

1. A `.folded` file reaches 33 MB at 99 Hz and 184 MB at 999 Hz.
2. One profile is valid for exactly one revision, one machine and one evaluator. A committed copy
   goes stale on the next commit, and no reader can tell.
3. The script plus a commit id re-derives it.

The **script** is the committed artefact. A ranked table graduates into `.worklog.md` while work
runs, and into `done.md` when the task closes.

### Acceptance test

On host `anji`, idle machine, warm store, `hack/eval-profile.sh` passes when all four hold:

1. It exits 0 and prints one output directory.
2. That directory holds a non-empty `profile.folded`, `profile.svg`, `stats.json` and `rank.txt`.
3. `rank.txt` names `nixpkgs/lib/sources.nix` as the top file by self time, at **25 % or more**.
   [research.md](research.md) measured **31.7 %**, so a 25 % floor leaves room for sample noise.
4. Both lock hashes match the start values.

Point 3 is the real test. It proves the harness reproduces the earlier finding.

---

## 2 — the universal-versus-den comparison

### What is compared

One host, two ways, one machine, one pinned revision, one evaluator:

| Side | Attribute |
|---|---|
| A | `.#darwinConfigurations.anji.config.system.build.toplevel.drvPath` |
| B | `.#denConfigurations.<the anji entity>.config.system.build.toplevel.drvPath` |

`anji` is the host, for one reason: side A already has a baseline of 64.07 s warm
([research.md](research.md) timing table, row 3). No NixOS host has a profile yet.

### The confounders, and how the design removes each one

| Confounder | The removal |
|---|---|
| Machine drift, thermal throttling | 5 measured runs, interleaved A-B-A-B-A. Median and range, never mean |
| A cold store | One discard run per side. Rows 2 and 3 show a 16 s cold-page penalty |
| The evaluation cache | `--no-eval-cache` on every call |
| A dirty tree | One pinned revision for the whole batch |
| A loaded machine | A load gate before the batch, and again between the two series |
| Two evaluators | One binary, and its version in the report header |
| A flake update mid-batch | The pinned revision fixes both lock files, and the lock guard proves it |
| Instantiation, which is 64 % of the Lix wall clock | Two separate series: plain and `--read-only`. Rows 3 and 5 are 64.07 s and 23.35 s |
| Parity | Three figures, never one. See below |
| The nixpkgs instance count | The "SELF TIME by source root" table of § 1, run per side |
| The nested-evaluation count | Not automated. The report prints a reminder to count by hand |

### Parity is the confounder that voids everything

A tree that implements less evaluates less, and it "wins" while doing nothing better. So
`hack/eval-compare.sh` prints three figures and no verdict:

1. **The raw series** — wall and user, median and range, per side, per series.
2. **The deterministic counters** — `cpuTime`, `nrFunctionCalls`, `nrThunks`, `nrAvoided`,
   `nrOpUpdateValuesCopied`. One run each: they repeat exactly, while the clock moved 25 % over the
   same runs.
3. **`cpuTime` per 1000 declared option leaves** — the normalised figure. A tree that is genuinely
   faster wins here too. A tree that only does less wins on figure 1 and ties or loses here.

**The script refuses to run without `--parity-confirmed`.** It exits 2 and names the blocker,
because the two trees are not at parity yet. Track parity in
[../generalization/definition.md](../generalization/definition.md).

### Acceptance test

Due now: without `--parity-confirmed` the script exits 2 and names the blocker. With the flag and
two attributes it writes a report that holds all three figures for both sides, from 5 interleaved
runs per side.

Due after parity: the run is valid only when the counters move in the same direction as the clocks.

---

## 3 — the `denLib.pairModules` lever

### The defect

`denLib.imports` starts a **fresh den library evaluation on every call** — the `eval` sits inside
the function, at `modules/den/lib.nix:483`. `denLib.pairModules` resolves **every** valid pair from
one shared `defaultDen` at `modules/den/lib.nix:423`, and `flake.denLib` is one
`import ./lib.nix`, so that evaluation happens at most once per Nix evaluation.

`checks/den-mvp/tests.nix` builds the `den-eval-instantiate` assertion with the per-call form, once
per aspect-class pair. The registry holds **205** aspects, and each one emits one to four classes.
So the check starts 205 or more den library evaluations where one is enough.

One detail: a call with an **empty** `aspects` list costs nothing, because `den` is never forced.
`checks/den-mvp/harness.nix` uses that form inside `bareShell`, and it is already free.

### The change

Three edits, all in the instantiate path of `checks/den-mvp/tests.nix`:

1. Read the class list from `denLib.pairs.${name}` instead of the local `aspectClassesOf`.
   `denLib.pairs` is `pairsFor defaultDen`, it carries den's own drift guard, and ten files under
   `assertions/` already use it.
2. Delete the local `aspectStructuralKeys` copy. Its own comment records the drift hazard.
3. Read the module from `denLib.pairModules."${name}-${class}"` instead of
   `denLib.imports { class; aspects = [ name ]; }`.

After the three edits the path costs **one** den library evaluation, shared with every other
`denLib.pairs` reader in the same build.

### Why it preserves behaviour

`pairModulesFor` builds each value as `resolve den class den.ful.kdn.${name}`. `denLib.imports`
builds the same expression for a single-aspect call with no `modules`, no `extraInputs` and the
default `select`. Both `den` handles come from `eval { }` with the same defaults.

Two real differences, both safe: `pairModules.<key>` returns the module and not a one-element list,
so the edit wraps it; and `pairClasses` throws on an unlisted class where the local helper stayed
silent, which is a strictly stronger guard.

### The proof — assertion counts, never a `drvPath`

A `drvPath` equality proof is invalid here: `kdnConfig.self` reaches the evaluated config, so any
edit changes every host's path. This change edits a check, so the check's own verdict is the proof.

| Step | Command | Record |
|---|---|---|
| 1 | `nix build --no-eval-cache -L '.#checks.aarch64-darwin.den-eval-instantiate'` | The `den eval instantiate: <N> of <N> assertions pass` line, verbatim, before and after. Same `N`, both `pass` |
| 2 | Compare the sorted pair-name list — it is the `expected` value of the one assertion, so it **is** the covered set | Identical before and after, or the change dropped coverage |
| 3 | `nix build --no-eval-cache -L --keep-going '.#checks.aarch64-darwin.bundle-den'`, then `bundle-core` | Every member passes. `bundle-den` reads `denLib.pairs` from ten files |
| 4 | Plant one `throw` in one aspect's `nixos` body, run step 1 | It fails on exactly that pair. The same method is recorded in the file for 2026-09-11 |

### Acceptance test, with the number

**`den-eval-instantiate` must fall from 358.0 s to 250.0 s or less** — a 30 % cut. Measure with
`nix build --no-eval-cache -L`, median of 3 runs, `aarch64-darwin`, warm store, idle machine.

- **358.0 s** is the current cost, from
  [../../../../checks/README.md](../../../../checks/README.md), measured 2026-09-11.
- **250.0 s** is a conservative target. The estimate behind it, unmeasured: the file records about
  +48 s for the 25 to 26 pairs of 2026-09-11, about 1.9 s per pair, and `modules/den/lib.nix`
  records one den library evaluation at about 1.0 s. So about half the per-pair cost is the
  duplicated evaluation, which predicts a saving near 180 s. 250.0 s asks for a third of that.

Two conditions ride with the number: `bundle-den` must not rise above its recorded 108.0 s, and the
`<N> of <N>` line must read the same `N`.

**Update the `den-eval-instantiate` row of `checks/README.md` with the real measured figure after
the change.** Never pre-write a number there.

### It lands last, and alone

`checks/den-mvp/tests.nix` feeds 23 named checks plus every area file under `assertions/`. A wrong
edit there breaks `bundle-den`, `bundle-core` and `bundle-slow` at once.

---

## 4 — the ranked scope

| Rank | Item | Value | Risk | Verdict |
|---|---|---|---|---|
| 1 | The profile harness and the ranker | High — every later cut needs it for exit criterion 5 | Very low — two new files, no evaluation path | Land now |
| 2 | These task documents | High — the task is parked with no `status.md` | None | Land now |
| 3 | `hack/eval-compare.sh` | Medium now, high later — a protocol in prose decays | Very low — it refuses to run | Land now, do not run |
| 4 | The `denLib.pairModules` lever | High — an estimated 180 s off a 358 s check | Medium — it edits the shared check harness | Land last, alone, with the four-step proof |
| 5 | The other 79 `denLib.imports` call sites in `checks/` | Medium — about 80 duplicated den evaluations | High — a site that passes `modules`, `extraInputs` or `select` cannot use `pairModules` | Defer to a sub-task, one area file per commit |
| 6 | Remove the devenv overlay from a host `pkgs` (about 17 %), and make the rosetta-builder image reference lazy (about 31 %) | Highest of all on the 64 s host figure | High — both change host output, so both need a closure proof | Defer. This is the item that meets exit criterion 1 |

**Item 6 holds the task's own exit criterion 1.** Items 1 to 5 touch the check tree, not a host
evaluation, so the task stays `status: in-progress` after this design lands.
