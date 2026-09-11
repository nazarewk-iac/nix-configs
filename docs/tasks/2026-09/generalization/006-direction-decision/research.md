---
type: Research
status: done
description: The measured evidence and the scored table for the slots-or-den direction decision, with every input that does not wait on task 004 criterion 3 or on task 005.
timestamp: 2026-09-11T12:00:00+02:00
authored_by: agent
---

# 006 — research: the evidence for the direction decision

Parent: [definition.md](definition.md). Gates: [004](../004-den-spike/definition.md) (status
`in-progress`) and [005](../005-conditional-imports-requirement/definition.md) (status `open`).

This file holds everything the decision needs that does **not** wait on those two gates. Section
[What this research cannot decide](#what-this-research-cannot-decide) names the rest.

Every number comes from a command that ran on 2026-09-11, between 10:30 and 11:10 local time. Other
agents write `modules/`, `checks/`, `templates/` and `data/` at the same time, so a count can move by
a few lines. Each row names its command, so a re-measurement is cheap.

## 1. Parity

| Measure | slots | den | Command |
|---|---|---|---|
| Module files | **19** slots + 1 loader | **21** aspects | `find modules/slots -name default.nix` (20), `ls modules/den/aspects` (21) |
| Nix lines | 3 686 | 5 815 | `find … -name '*.nix' -print0 \| xargs -0 wc -l` |
| Shared assets (`.sh`, `.py`) | 927 lines, 9 files | reads all 9 | `find modules/slots -type f \( -name '*.sh' -o -name '*.py' \)` |
| README lines | 844 (6 files) + `lib/slots` 72 | 346 (1 file) | `wc -l` |
| Valid target pairs | 26 target keys across 19 slots | **26** (aspect, class) pairs | see below |

`modules/slots/default.nix` is the loader, not a slot. So the slot count is 19, and the 006
definition's "12 of 19 slots target devenv" figure is right.

**Aspect coverage is complete, and it goes further.** The 21 aspect names cover all 19 slots
one-to-one, and they add two aspects with no slot behind them: `homebrew` and `homebrew-nix-managed`.
Those two come from `modules/universal`, not from `modules/slots`.

**The 26 pairs.** `modules/den/lib.nix` builds the pair list from the aspect itself, not from a hand
list. `nix eval --no-eval-cache --json '.#denLib.pairs'` returns:

| Class | Pairs | Aspects |
|---|---|---|
| `devenv` | 14 | devenv-cli, gh, jj, jj-fork, llm-client, llm-proxy, mcp, mcp-basic-memory, mcp-pretty-print, mcp-snoop, nix, opencode, ssh-access, zellij |
| `nixos` | 4 | ca, devenv-cli, llm, llm-proxy |
| `darwin` | 4 | devenv-cli, homebrew, homebrew-nix-managed, rosetta-builder |
| `homeManager` | 4 | devenv-cli, signing, ssh-access, ssh-agent |

Total 26. `nix eval '.#denModules' --apply 'x: builtins.length (builtins.attrNames x)'` returns
**43** keys: the 26 explicit `<aspect>-<class>` keys plus 17 short zero-argument keys for the aspects
that emit exactly one class.

`lib.nix:187` states "26 keys, from 21 aspects", and a comment three lines lower still says "all 25
keys of that day". The live measurement is 26. The stale "25" is a comment defect, not a code defect.

**One parity gain, measured.** The `devenv` slot emits `nixos`, `darwin` and `home` — no `devenv`
target. The `devenv-cli` aspect emits all four classes. So the aspect reaches one target the slot
cannot.

**One parity gain in the `mcp` family.** `modules/slots/mcp/default.nix:157-183` states that
`mcp-servers-nix` is unreachable from the slot: `flake.mkSlots` hardwires `specialArgs.inputs` to the
`flake.nix` input set, and the input lives in `devenv.yaml` only. So every `kdn.mcp.programs` entry
is inert on the slot route, for every consumer, this repository included. The aspect declares
`kdn.mcp.serversNix`, so a consumer supplies the source. The slot's own warning text names the aspect
as the fix.

## 2. Real consumers today

| Route | Hosts | Other call sites |
|---|---|---|
| slots | **5** host directories: anji, brys, oams, orr, the work host | 13 `mkSlots` call sites in 13 files |
| den | **1** host directory: orr | 6 den entities in `checks/den-mvp/`, plus 1 template |

`grep -rn mkSlots --include='*.nix' .` finds 13 call sites: `devenv.nix:31`,
`hosts/anji/default.nix:13`, `hosts/brys/default.nix:9`, `hosts/brys/devenv.nix:21`,
`hosts/brys/llm-minimal.nix:21`, `hosts/oams/default.nix:9`, `hosts/oams/devenv.nix:17`,
`hosts/orr/default.nix:23`, the work host's `default.nix:12`, `checks/standalone.nix:147`,
`checks/jj-experiments/render-fork-config.nix:34`, `templates/adopter/devenv.nix:32`, and one in
`data/slots-ssh-access.nix` documentation. Two files declare the function (`flake.nix:309`,
`lib/slots/default.nix:6`) and three pass it through (`checks/default.nix:56`,
`checks/jj-experiments/devenv.nix:13`, `checks/jj-experiments/subset-runner.nix:26`).

`grep -rn 'denLib\|denModules' hosts/` finds one host: `hosts/orr/default.nix:36,40`. That host runs
**both** routes at once, behind one switch — `hosts/orr/default.nix:15` states that the two branches
stay lazy, so the unused route costs no evaluation.

`nix eval '.#denConfigurations' --apply builtins.attrNames` returns `host-darwin`, `host-nixos`.
`nix eval '.#denDevenvShells' --apply builtins.attrNames` returns `devenv-darwin`, `devenv-linux`,
`host-darwin`, `host-nixos`. All six live in `checks/den-mvp/`; none is a real machine.

**So the consumer count favours slots today, and only today.** The den tree carries no production
host. The slots tree carries five.

## 3. Test coverage

`nix eval --no-eval-cache '.#checks.<system>' --apply 'x: builtins.length (builtins.attrNames x)'`:

| System | Checks |
|---|---|
| `aarch64-darwin` | **33** |
| `x86_64-linux` | **33** |
| `aarch64-linux` | **28** |

The 5-check difference is the artifact and smoke family. `aarch64-linux` gets no
`den-artifact-*` and no `den-smoke-*` check, because no den entity targets that system.

Which route each family covers:

| Family | Count on darwin | Route it covers |
|---|---|---|
| `den-eval-*` | 21 | den |
| `den-artifact-*` | 3 | den |
| `den-smoke-*` | 2 | den |
| `den-mvp` | 1 | den (build gate for all den entities of this system) |
| `standalone-aspects` | 1 | den (the three aspect rules) |
| `standalone-slots` | 1 | slots (the standalone rule) |
| `jj-experiments-pytest` | 1 | slots (`render-fork-config.nix` renders through `mkSlots`) |
| `hello`, `kdn-slug-pytest`, `zellij-llm-pytest` | 3 | neither — plumbing and packages |

**28 of 33 checks cover den. 2 cover slots.** The test investment is already almost entirely on the
den side: `checks/den-mvp/` holds 3 805 lines, of which `tests.nix` is 2 925. `checks/standalone.nix`
is 291 lines and it serves both trees.

`checks/den-mvp/tests.nix:2748` holds a coverage tripwire: every registry aspect must name the entity
whose target module it evaluates. `den-eval-instantiate` forces every (aspect, class) pair straight
from the registry, so the guard cannot rot. The slots tree has no equivalent.

## 4. The adopter cost of each route

**slots: an overlay is mandatory.** `grep -rn 'pkgs\.kdn\.' modules/slots/` returns 11 real code
hits in **7** slot files: `jj/default.nix:132`, `llm/default.nix:878`, `llm/proxy/default.nix:84`,
`mcp/basic-memory/default.nix:16`, `mcp/snoop/default.nix:28,34`, `ssh-access/default.nix:42,47`,
`zellij/default.nix:77,78`. `templates/adopter/devenv.nix:14` names this a "HARD REQUIREMENT" and
tells the adopter to add `overlays.packages` and not `overlays.default`.

**den: no overlay.** `grep -rn 'pkgs\.kdn\.' modules/den/` returns 10 hits, and **every one is a
comment**: one line of `modules/den/README.md` and nine comment lines in six aspect files. No aspect
reads `pkgs.kdn`. Seven aspect files call the package with a relative path instead —
`pkgs.callPackage ../../../packages/<name> { }` at `jj.nix:95`, `llm.nix:95`,
`llm-proxy.nix:128`, `mcp-basic-memory.nix:70`, `mcp-snoop.nix:36`, `ssh-access.nix:137`,
`zellij.nix:74,75`.

`grep -rn 'lib\.kdn\.' modules/slots/` returns 0. `grep -rn 'lib\.kdn\.' modules/den/` returns 1.
So neither route forces the extended `lib`.

Cost, side by side:

| Adopter cost | slots | den |
|---|---|---|
| `imports` lines for one small feature | 3 (`mkSlots` call, `.config.devenv`, overlay) | **1** (`denModules.gh`) |
| Overlay | **required** | none |
| `pkgs` argument | required | none |
| Template size | 48 lines | 55 lines |
| Feature switch | `kdn.<slot>.enable = true` | inclusion in `imports` |
| Files it writes into the tree, by default | agent rules and skills, because `kdn.isSourceRepo` defaults to `false` and `false` means "install them" | one file, `.claude/settings.json`; five aspects gate their rule files behind `installAgentRules`, and all five default to **false** |
| `mcp-servers-nix` | no option exists, so `kdn.mcp.programs` stays inert | `kdn.mcp.serversNix` takes the adopter's own source |
| Lock cost | this repository's whole lock | 103 lock nodes, per `docs/den-for-adopters.md:523` |

The default-file direction is the sharper difference. On the slot route the adopter opts **out** of
the author's agent rules. On the den route the adopter opts **in**.

## 5. The retirement cost

### If den wins

| Action | Lines |
|---|---|
| Delete `modules/slots/**/*.nix` | 3 686 |
| Delete `lib/slots/{default,schema}.nix` | 72 |
| Delete the 6 slot `README.md` files | 844 |
| Delete `templates/adopter/` | 114 |
| Delete `docs/slots-for-adopters.md` | 249 |
| **Move**, not delete: the 9 shared `.sh` and `.py` assets | 927 |
| **Rewire**: 13 `mkSlots` call sites in 13 files | — |
| **Rewire**: `flake.mkSlots` at `flake.nix:309-333` | 25 |

Total deleted: about **4 965** lines. Total moved: **927** lines.

**The 927 lines block a naive delete.** Six aspect files already read all nine assets by relative
path: `jj.nix:104`, `jj-fork.nix:95,105,130`, `mcp-pretty-print.nix:146`, `nix.nix:82`,
`signing.nix:179`, `zellij.nix:83,92`. A delete of `modules/slots/` breaks nine `builtins.readFile`
and path references at once. So the strangler-fig sequence must move the assets **first**, in a
separate commit, and re-point the nine references.

The consumer rewire is the real work, not the delete. Nine files carry a live `mkSlots` call that a
host or a shell depends on: `devenv.nix`, four host `default.nix` files, two host `devenv.nix` files,
`hosts/brys/llm-minimal.nix`, and the work host's `default.nix`.

### If slots wins

| Action | Lines |
|---|---|
| Delete `modules/den/` | 5 815 nix + 346 README |
| Delete `checks/den-mvp/` | 3 805 |
| Delete `docs/den-for-adopters.md` | 661 |
| Delete `templates/adopter-den/` | 120 |
| Delete the `standalone-aspects` half of `checks/standalone.nix` | part of 291 |
| Drop 2 flake inputs (`den`, `nix-effects`) | `flake.nix:52,73` |
| Rewire: `hosts/orr/default.nix` back to one route | part of 98 |
| Rewire: `flake.nix:186` drops the den flake-module import | 1 |

Total deleted: about **10 750** lines. One consumer file changes.

**So the retirement is asymmetric.** A slots win deletes twice as many lines and touches one
consumer. A den win deletes fewer lines, moves 927, and rewires 13 call sites in 13 files. The
asymmetry exists because the den tree is still additive and carries no production host.

## 6. The framework risk

Every fact below comes from this repository or from den's own source in the nix store at
`/nix/store/6zvwis9ybb9iy0vypb7v798109gshffl-source`.

**The pin.** `flake.nix:52` pins den by revision, with no branch reference:
`github:denful/den/d50f0fce6fc1a8ba00fd0d310746d0e8ecc2f70d`. `flake.lock` records
`lastModified = 1788557660`, which is **2026-09-04T21:34:20Z**. `flake.nix:73` pins
`denful/nix-effects` by revision too, because den otherwise fetches it with `builtins.fetchTarball`
at evaluation time and no consumer lock records that fetch. So no automatic drift can reach this
repository. An update is always a deliberate act.

**The resolve entry point is documented as not public.** Two den documentation pages say so:

- `docs/src/content/docs/reference/aspects.mdx:252` — "Resolution is handled internally by the fx
  pipeline. `den.lib.aspects.resolve` still exists but is not a public API — call it directly only if
  you are building custom pipeline stages."
- `docs/src/content/docs/guides/debug.md:104` — "Note: `den.lib.aspects.resolve` is internal to the
  pipeline."

`docs/src/content/docs/reference/lib.mdx:31,37,45` marks three sibling functions **Internal**.

This repository calls `resolve` at three sites: `modules/den/lib.nix:128`,
`modules/den/flake-module.nix:95`, and a reference in `modules/den/classes/devenv.nix:17`.

**The full upstream contact surface is 7 symbols.** A `grep -rn 'inputs\.den'` over `modules/den/`
returns:

| Symbol | Sites | Public? |
|---|---|---|
| `inputs.den.namespace` | `namespaces.nix:56,57`, `lib.nix:112` | yes |
| `inputs.den.nixModule` | `lib.nix:109,270` | yes |
| `inputs.den.flakeModule` | `flake-module.nix:49` | yes |
| `inputs.den.flakeOutputs.*Configurations` | `flake-module.nix:53,54` | yes |
| `import (inputs.den + "/modules/aspects.nix")` | `lib.nix:72` | **a path into den's own tree** |
| `den.lib.aspects.resolve` | `lib.nix:128`, `flake-module.nix:95` | **documented as not public** |
| `den.lib.policy.instantiate` | `classes/devenv.nix:159` | not marked internal |

The path import at `lib.nix:72` is the deepest coupling. It reaches a file inside den's `modules/`
directory, and den's own module list is free to move it.

**The release history.** Facts only:

- **No CHANGELOG.** `ls` of den's source root shows no `CHANGELOG`, no `NEWS` and no release-notes
  file. `docs/src/content/docs/releases.mdx:74` points a reader at the GitHub releases page instead.
- **v0.x, and fast-paced by policy.** `releases.mdx:10-17` states the v0 series, and it states that
  development is "fast-paced, evolving and being shaped by its current users".
- **`main` moves on every merge.** `releases.mdx:36-39` states that `inputs.den.url =
  "github:denful/den"` "updates on each PR merge".
- **The upstream breaking-change channel is a discussion label, not a file.** `releases.mdx:44-46`
  says that a PR "might introduce changes that require you being aware", and it routes those to
  GitHub discussions with the `heads-up` label, plus Zulip and Matrix.
- **A whole reference page is deprecated.** `docs/src/content/docs/reference/lib-deprecated.mdx`
  covers `den.lib.parametric` (4 functions), `den.lib.canTake` (4), `den.lib.take` (4), and the
  `perHost`/`perUser`/`perHome` context shortcuts. `lib-deprecated.mdx:20` says each call logs a
  deprecation warning.
- **One removal is in flight.** `docs/src/content/docs/guides/migrate-ctx.mdx:29-32` states that a
  compatibility shim keeps `den.ctx` configs alive "during the transition", and that the shim "is
  scheduled for removal".
- **Neither in-flight change touches this repository.** `grep` finds no use of `den.ctx` and no use
  of any deprecated `den.lib.*` function in `modules/den/`. The only `ctx` hits are the unrelated
  Python plugin contract in `mcp-pretty-print.nix` and a `llama.cpp` flag in `llm.nix`.
- **den declares no flake input of its own.** `releases.mdx:21-23` states it, and `flake.nix:50-51`
  repeats it.
- **The 004 spike recorded two more items** that this file does not re-measure: commit `6254414`
  changed `resolve`'s arity from 3 to 2 with no changelog entry, and discussion #569 stayed
  unanswered for 3.5 months. Source: `../004-den-spike/definition.md`.

**The measured verdict on risk.** The technical coupling is small and named: 7 symbols, 2 of them
outside the public surface. The pin is by revision, so drift is opt-in. The gap is process: no
changelog, a chat-channel announcement model, and a live deprecation programme with no dates. A
break arrives silently at update time, and this repository's 33 checks are the only detector.

## 7. The scored table

Weight 5 is decisive. Weight 1 is a tie-breaker. A score is 0 to 5, where 5 is best. Row 1 stays
unscored, because it waits on the gates.

| # | Criterion | Weight | slots | den | Evidence |
|---|---|---|---|---|---|
| 1 | Satisfies the 005 conditional-imports requirement | 5 | — | — | 005 is `open`; 004 criterion 3 is `BLOCKED`. Not scorable. |
| 2 | An adopter imports a drop-in and learns no framework | 5 | 3 | **5** | den: 1 `imports` line, no `pkgs`, no overlay. slots: 3 lines plus the overlay. |
| 3 | A devenv target exists | 4 | **5** | **5** | slots: 12 of 19 slots. den: 14 of 26 pairs, plus `devenv-cli`, which the slot lacks. |
| 4 | Parity for the pieces this repository keeps | 3 | **5** | **5** | 19 of 19 slots have an aspect; den adds 2 more and one extra class. |
| 5 | Adopter cost outside the import line | 3 | 2 | **5** | 7 slot files force `overlays.packages`. den has 0 real `pkgs.kdn` hits. |
| 6 | Automated test coverage today | 3 | 2 | **5** | 28 of 33 checks cover den; 2 cover slots. `den-eval-instantiate` forces every pair. |
| 7 | Live consumers in this repository | 2 | **5** | 2 | slots: 5 hosts, 13 call sites. den: 1 host, and it runs both routes. |
| 8 | API stability of the substrate | 4 | **5** | 2 | slots: a 72-line schema this repository owns. den: v0.x, `resolve` not public, no changelog. |
| 9 | Maintenance burden over time | 3 | 2 | 4 | slots: every future need is local work. den: shared upstream, with drift risk. |
| 10 | Retirement cost when this route wins (cheap is better) | 2 | 4 | 3 | slots wins: delete about 10 750 lines, 1 consumer changes. den wins: delete about 4 965, move 927, rewire 13 call sites. |
| | **Weighted total, of 145** | 29 | **106 (73 %)** | **120 (83 %)** | |

Row-by-row weighted contribution:

| # | Weight | slots | den |
|---|---|---|---|
| 2 | 5 | 15 | 25 |
| 3 | 4 | 20 | 20 |
| 4 | 3 | 15 | 15 |
| 5 | 3 | 6 | 15 |
| 6 | 3 | 6 | 15 |
| 7 | 2 | 10 | 4 |
| 8 | 4 | 20 | 8 |
| 9 | 3 | 6 | 12 |
| 10 | 2 | 8 | 6 |
| **Total** | **29** | **106** | **120** |

## 8. Recommendation

**Choose den, and treat row 8 as a cost you pay with tests and a pinned revision, not as a defect
you can remove.** den wins the two heaviest scorable rows outright: the adopter imports one line with
no overlay and no `pkgs` (row 2, weight 5), and 28 of the 33 checks already guard that route (row 6).
It matches slots on the devenv target and on parity, and it already exceeds parity in two measured
places — the `devenv-cli` aspect reaches a class the `devenv` slot cannot, and `kdn.mcp.serversNix`
makes the `mcp` family reachable where the slot's own warning admits it is inert. slots wins only on
substrate stability and on the consumer count, and the consumer count is a snapshot of a
half-finished migration, not a property of either design. The pin by revision at `flake.nix:52` plus
the 2 explicit inputs already convert den's upstream churn into a deliberate, testable update event.

**The exact condition that reverses this.** Reverse to slots when, and only when, 005 states a
conditional-imports requirement that den cannot satisfy through a **public** interface — that is,
when the only den route to a data-driven `imports` list runs through `resolve`, through
`den.lib.policy.instantiate`, or through a deeper path import than `lib.nix:72` already uses. In that
case the reversal is correct even though den scores 14 points higher, because row 1 carries weight 5
and it is a gate, not a score. A second, independent reversal trigger: an upstream change that breaks
two or more of the 7 contact symbols in one update, because that turns row 8 from a managed cost into
recurring unplanned work.

## What this research cannot decide

Three things stay open, and no measurement here can close them.

**1. Row 1 of the scored table — the 005 requirement.** 005 has status `open`, so the requirement
does not exist in a testable form yet. 004 records criterion 3 as `BLOCKED on 005, not tested`. So
this file cannot say whether den reproduces what `modules/meta` does: a separate `lib.evalModules`
universe with `class = "kdn-meta"` that runs **before** the NixOS, Darwin and Home Manager
evaluation, and that injects the result as `specialArgs.kdnConfig`. The payoff of that order is a
static-data `imports` list, as at `modules/universal/profile/hardware/rpi4/default.nix:22`. Row 1
carries weight 5 and it is a gate. A failure there reverses the recommendation on its own.

**2. The cost of the slots alternative, if row 1 fails.** The 006 definition asks what a new slots
mechanism would cost. That cost is a function of the requirement 005 writes. `lib/slots/schema.nix`
is 21 lines and `lib/slots/default.nix` is 51, so the base is small — but nobody can size an
extension to an unwritten requirement. This file records the base only.

**3. Whether the adopter boundary survives either choice.** The definition's closing constraint says
the adopter entry point must not force the adopter to learn the framework choice. 001 and 002 both
have status `open`, and they establish that boundary. The two templates measure the *current* cost of
each route — 1 import line for den, 3 plus an overlay for slots — but the boundary itself is not
ratified yet. So this file scores the cost, not the constraint.

One smaller unknown, for completeness: the 004 spike measured den's adopter path with a **warm**
store. A cold first fetch of the 103 lock nodes stays untested, per
`docs/den-for-adopters.md:544-546`.
