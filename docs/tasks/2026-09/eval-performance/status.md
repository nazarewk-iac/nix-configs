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

## Update 2026-10-30 — new avenues from the Kagi research

This update adds avenues only. **No measurement was taken for any item below.** Every number is
either quoted from the source with its reference, or it is `TBD`. The source is
[research.kagi.md](research.kagi.md), a secondary digest of one Kagi Assistant session dated
2026-09-11. That session is an LLM answer with web references. It did not run here, and it did not
see this repo. Treat each item as a claim to check.

The system evaluator today is **Lix 2.95.3** (`nix --version`). [research.md](research.md) measured
on 2.95.2, one patch release earlier.

### The newly identified avenues

1. **A non-Lix client for parallel evaluation.** The session corrects its own earlier claim: parallel
   evaluation and lazy trees are **client-side**, not daemon-side. So a Determinate Nix or upstream
   Nix ≥ 2.35 client against the Lix daemon is plausible. The protocol is frozen at CppNix 2.18, and
   [research.md](research.md) already ran a CppNix 2.35.2 client against this daemon. That proves
   the protocol, not the parallelism. The `fix` benchmark also shows parallel eval is **not** a win
   for one NixOS config.
2. **`fix` as an evaluator for profiling.** A Zig evaluator with `-Dprof-path` (per forcing site,
   approximate), `--timeline` (Perfetto), `--stats` and a debugger. Alpha. Its own `.drv` equality
   safety test fits the `drvPath` caveat in [definition.md](definition.md): valid on a den host, not
   on a universal host.
3. **Lix 2.96 mimalloc.** The session claims 2.96 links mimalloc and gains 5–12 % wall clock on
   evaluation, including full NixOS configs. This is a package bump, not a config change.
4. **`GC_INITIAL_HEAP_SIZE`.** Default is 384 MB. One source reports `4G` cut `nix eval` wall time by
   about 25 %. [research.md](research.md) measured `gc.heapSize` at 4.85 GB. Untested here.
5. **A config audit.** Duplicate nixpkgs imports (the devenv overlay finding, under another name),
   `useGlobalPkgs`, flake `packages` access, and specialisations and containers. **`specialisation.llms`
   at `hosts/brys/default.nix:370` runs with `inheritParentConfig = false`, so the session's claim
   means `brys` evaluates a full extra NixOS config.**
6. **The eval/build/activation split.** The session rates "measure where time goes" as rank 1 and
   says activation can exceed 1.5 min. This repo's rebuild wrappers never split the three phases.

### Ranked experiment backlog

Rank is by expected value per unit of risk, not by expected size. Each item is one experiment with
one number.

| Rank | Change                                                                                                                                                                                                                         | Acceptance                                                                                                                  | Rollback                                                                                                                | Risk                                                                                                                                                                                                                                                                           |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1    | **Upgrade Lix to 2.96** in the flake input. Then re-run `hack/eval-profile.sh` on `anji`.                                                                                                                                      | Warm `anji` wall falls by **TBD — measure**, target ≥ 5 % (the source's floor for mimalloc)                                 | Revert the flake input and `flake.lock`; the store keeps the old Lix (verified present today at 2.95.3)                 | Low. A nixpkgs availability gap for 2.96 is the only blocker. Same store protocol, same CLI. No host output change                                                                                                                                                             |
| 2    | **Set `GC_INITIAL_HEAP_SIZE` in the rebuild wrapper.** Add an `export` to `nixos-rebuild.sh` and `packages/darwin-rebuild/darwin-rebuild.sh`, or to the `pre_cmd` arrays.                                                      | Warm `anji` wall falls by **TBD — measure**, at a chosen heap size (start 4 GiB, then 8 GiB)                                | Remove the `export`; it changes no evaluated config                                                                     | Low. Trades RAM for speed. Under `sudo`, confirm the variable survives. Confirm Lix honours it as Boehm GC would                                                                                                                                                               |
| 3    | **Measure the eval/build/activation split.** Time `nix eval` of `.drvPath`, then `nix build`, then the switch step, as three separate numbers.                                                                                 | The three shares are recorded for one host in `.worklog.md`; each share is **TBD — measure**                                | None. A measurement only, no code change                                                                                | None. Read-only. It reframes exit criterion 1 against the whole update, so record it before the next cut                                                                                                                                                                       |
| 4    | **Audit duplicate nixpkgs imports and specialisations.** Count distinct nixpkgs store roots per host profile. Check `useGlobalPkgs`, flake `packages` access, and every `specialisation.*` (`brys` has `specialisation.llms`). | A list of each duplicate import and each specialisation, with its measured self-time share. Each share is **TBD — measure** | None for the audit. Any cut needs a closure proof, per exit criterion 3                                                 | Medium for cuts, none for the audit. A cut to `specialisation.llms` changes `brys` output. A cut to a nixpkgs import changes a host closure. Prove with a closure comparison, never a `drvPath` on a universal host                                                            |
| 5    | **Time a non-Lix client against the Lix daemon, then check `.drv` equality.** Fetch `nixpkgs#nixVersions.latest`, run with `--no-eval-cache`, and compare its `.drvPath` with Lix's on a fixed revision.                       | Two numbers: warm wall for each client (**TBD — measure**), and `.drvPath` equality true or false                           | None. A measurement only. Use `--no-write-lock-file --no-update-lock-file --offline` as [research.md](research.md) does | Low for the timing. The equality check needs a quiet tree. `[research.md](research.md)` recorded a different `drvPath` between evaluators on a dirty tree, so this re-tests it clean. A den host is the valid comparison; a universal host is not, because of `kdnConfig.self` |
| 6    | **Evaluate with `fix`, gated on `.drv` equality.** Use `fix` for evaluation only, keep `nixos-rebuild` and `darwin-rebuild` for activation.                                                                                    | `fix`'s `.drvPath` equals the normal one on a fixed revision, and its warm wall is **TBD — measure**                        | Drop `fix`. It is an experiment, not a system dependency                                                                | High. It is alpha, tested mainly on x86_64 Linux, and `local`/`auto` stores are unsupported. Gate on `.drv` equality and never activate with it                                                                                                                                |

### Order notes

- Items 1 and 2 are the only ones that can move exit criterion 1 without a closure proof, because
  neither changes an evaluated config. Do them first.
- Item 3 must land before items 4 to 6 read as wins. Without the split, a faster eval may not mean a
  faster update.
- Item 4's cuts carry the same closure-proof obligation as the unstarted devenv-overlay lever. Keep
  them behind that lever unless the audit shows a bigger, safer win.
- Item 5 repeats what [research.md](research.md) could not prove: whether a non-Lix evaluator agrees
  on a `.drvPath` for the same input. Run it on a fixed revision.
- Item 6 needs item 5's result first, because `fix` is one more non-Lix evaluator to trust on
  `.drvPath`.

All six items keep the existing rule: no number goes into `checks/README.md` until it is measured
here.

## Update 2026-11-09 — machine-difference estimate + pkgs-pinning link

- Added [machine-differences.md](machine-differences.md): measured eval-only baselines for all six
  hosts (moss 70 s, etra 82 s, briv 84 s, oams 148 s, brys 240 s, anji 242 s) and a ranked estimate
  of why they differ. Top cause is **boot specialisations** (brys 4, oams 1) — each is a whole extra
  config eval, orthogonal to nixpkgs instantiation.
- The **pinned-pkgs** task ([../../2026-11/pinned-pkgs-single-instantiation/](../../2026-11/pinned-pkgs-single-instantiation/definition.md))
  is lever **L2** here: one `pkgs` per `(system, variant)`, shared by every host of a system. It is
  the lever that makes a **fleet-wide single-process eval** cheap (the compounding case: all-six in
  one eval was ~90 s vs ~590 s summed). Its isolated den-root design is
  [design-den-root.md](../../2026-11/pinned-pkgs-single-instantiation/design-den-root.md).
- Blocker recorded: the **age `sops`-wrapper overlay is host-config-dependent** (only brys enables
  age), so brys cannot share a static per-system pkgs until that wrapper leaves `nixpkgs.overlays`.

## Update 2026-11-16 — the parent/Home Manager split, as an inventory

Idea recorded, no measurement: evaluate the parent system and every Home Manager user as **separate
flake outputs**, and deploy both from one wrapper by default (`--parent-only`, `--home-only` on
demand). The full note is [hm-split.md](hm-split.md).

- **A naive measurement fails, and the failure is the finding.** `oams` with
  `home-manager.users = lib.mkForce { }` dies at `modules/universal/programs/atuin/default.nix:268`,
  which reads `config.home-manager.users.<user>.xdg.dataHome`. The dependency runs both ways.
- **The inventory is the starting point.** Parent → Home Manager: **60 `ifHMParent` uses**,
  **138 `home-manager.sharedModules` uses across 113 files**, **31 `home-manager.users` occurrences
  in 20 files**. Parent reads Home Manager back at **5 sites** (`disks` ×3, `atuin` ×1, den `disks`
  ×1). Home Manager → parent has **5 real `osConfig`/`kdnConfig.parent` reads** plus **3 dead
  bindings** (kanshi's unused arg, two unused `sysCfg`).
- **The den tree is the precedent.** It already removed the `osConfig` nixpkgs bridge, the Firefox
  and Thunderbird policy reads, and the atuin `xdg.dataHome` read, and it already emits
  `denHomeConfigurations`. Its one leftover is the persistence read-back.
- **The tooling is the small part.** Sketch in [hm-split.md](hm-split.md) § "The deploy tooling":
  discovery from `meta.json`, parent first, one lock, one exit code, and the host `pkgs` passed into
  every user so no second nixpkgs instance appears.
- **Order:** wire one `hosts-den` host with a den user and one standalone home config, invert the
  persistence read-back, prototype the wrapper, then measure the three attributes of
  [hm-split.md](hm-split.md) § "The measurement that would work".
- **Correction:** the `useGlobalPkgs = false` row in [research.md](research.md) is stale. Commit
  `ed3517329` (2026-11-09) turned it on. The row now says so.

## Update 2026-11-16 — persistence without reading Home Manager

The persistence read-back is now designed, in [design-persistence.md](design-persistence.md). No
code changed.

- **The read is smaller than the first inventory said.** The parent reads
  `hmConfig.kdn.disks.persist.<bucket>.{files,directories}`, not `home.file`. No Home Manager code
  ever reads that option, and nothing reads `kdn.disks.enable` either.
- **Every app entry is home-relative, and most are XDG-prefixed.** `kdn.apps` prefixes `dirs.cache`
  with `.cache`, `dirs.config` with `.config`, `dirs.data` with `.local/share`, `dirs.state` with
  `.local/state` (`apps/default.nix:57-71`). An entry that starts with `/` has the slash stripped
  (`:22-30`), so it lands at the home root: `.thunderbird`, `.mozilla/firefox`, `.omp`, `.pi`,
  `.claude`, `.wine` are exceptions, not XDG-covered. The review caught this.
- **Recommended design — R1:** persist the four XDG dirs, the media dirs, `.ssh` and `.gnupg` per
  user, all host data, plus a per-module host-branch entry for the roughly ten paths outside XDG
  (`.aws`, `.java`, the shell histories, `dev`, `Games`). `userDefaults.persist` already exists in
  den; universal only needs the port.
- **The migration is mostly deletion.** About twelve `kdn.apps` lists and forty universal / twenty
  den user-scope writes go away; about ten universal exceptions move to a host branch. The two
  `home-manager.users` name reads and the service-ordering read move to `cfg.users` filtered to
  normal users, with `root` explicit.
- **Whole-directory persistence has four real costs** the first draft understated: paths that
  modules deliberately put in a different bucket (Steam/lutris/bottles in `usr/cache`), secrets under
  `.config` (the rosec age key), `.local/state` turning HM generations into gc roots, and
  `hmbackup` files no longer wiped per boot. All four are now recorded.
- **Atuin is a free win.** Its unit script resolves `xdg.dataHome` at evaluation time; it can read
  `${XDG_DATA_HOME:-$HOME/.local/share}` at runtime instead, removing one of the seven read sites
  with no design decision.
- **The proof is the same A/B that failed:** empty `home-manager.users` must evaluate. It does not
  today; it dies at `atuin:268`. Run it on `etra`, not `oams`: `oams` uses
  `kdn.fs.disko.luks-zfs.enable`, which excludes `kdn.disks.enable`, so its persistence blocks are
  never forced (the review caught this too).
- **A review pass found and fixed:** the missed `hasParentOfAnyType` predicate (32 sites), a wrong
  read-site count (5 vs 7), the overstated standalone Firefox/Thunderbird losses, a wrong `osConfig`
  grep count (34 vs 28), the invalid `oams` proof host, and a missing sops hazard (no Home Manager
  key source exists).
