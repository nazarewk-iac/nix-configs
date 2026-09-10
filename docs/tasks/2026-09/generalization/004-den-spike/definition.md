---
type: Task
description: Evaluate the denful/den framework as the reimplementation target before any module rewrite starts, with a drop-in import test as the decisive criterion.
status: in-progress
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 004 — den spike

Hub: [the generalization umbrella task](../definition.md). **Run this as early as possible.**
Together with 005 it gates 006.

Goal: decide whether `denful/den` can be the target framework, before anybody rewrites a module.

## Phase 1 verdict — 2026-09-10

Measured in scratch flakes under `/tmp/den-spike/`, on den `main` and on v0.18.0. Every command
and output is in [research.md](research.md). No file in this repository changed.

| Criterion | Verdict |
|---|---|
| 2 — an adopter imports a resolved aspect, with no den in their own code | **PASS**, with two limits |
| 1 — a `devenv` class can exist | **PASS** |
| 3 — the conditional-imports requirement | **BLOCKED** on 005, not tested |
| 4 — the 1→N mixed-aspect collision | **REFUTED** — it does not reproduce |

The kill criterion does not fire. So phase 2 starts: build `modules/den/` additively.

**The two limits on criterion 2.** An entity-parametric aspect (`{ host, ... }`) and a den battery
both drop to `{ imports = [ ]; }` across the boundary, with no warning and no error. The same
aspects work inside den. Two workarounds are verified: the producer pre-binds a host with
`den.lib.resolveEntity`, or the producer exports `<host>.mainModule` (whole-host granularity).
Second, den stays a transitive lock node in the adopter's own lock — a module is a closure, so no
serialization removes it. The claim holds for the adopter's code and concepts, not for their lock.

**The "Internal" label is a stability warning, not a correctness warning.** den's own
`modules/outputs.nix` calls `resolve`; the documented alternative `mainModule` is a one-line
projection of the same code and is also `internal = true`;
`explanation/library-vs-framework.mdx` recommends it with no caveat. But there is no CHANGELOG,
and commit `6254414` silently changed the arity from 3 to 2. Discussion #569 is still unanswered
after 3.5 months, and the author's only reply links the page that warns against production use.
So the technical risk is low and the social risk is high.

**A new risk this spike found.** `nix/lib/fx.nix` fetches `denful/nix-effects` with
`builtins.fetchTarball` at evaluation time, keyed off den's own vendored
`templates/ci/flake.lock`. No consumer lock records it. Reproduced with a `nix-effects`-free
flake that still evaluates. So phase 2 must declare `nix-effects` explicitly.

**Five conditions on phase 2**, from the spike and from the creator's preference:

1. Assert every exported module has a non-empty `imports` list. The silent-empty failure above is
   otherwise invisible.
2. Keep an adopter-facing aspect free of entity data. Use a plain option instead.
3. Declare `nix-effects` as an explicit input.
4. Leave criterion 3 open until 005 states the conditional-imports requirement.
5. **Ship the adopter path as a den-resolved plain module.** The creator stated the preference on
   2026-09-10: an adopter should use the den config once the spike works out. So phase 2 owns an
   adopter-facing flake output that runs `den.lib.aspects.resolve` on this side of the boundary. The
   adopter imports a plain module, and the adopter never adopts den. That is criterion 2's measured
   shape, so treat this as a deliverable, not an experiment. Condition 1 is the guard that stops the
   silent-empty failure from reaching an adopter.
   [../../../slots-for-adopters.md](../../../slots-for-adopters.md) documents the interim `mkSlots`
   route, and it must gain the den route when phase 2 lands it.

## Phase 2 — milestone 1 lands — 2026-09-10

`modules/den/` now exists. It holds the loader, one class, one aspect and one host. See
[modules/den/README.md](../../../../modules/den/README.md) for the layout, the status table and the
verification commands. Five conditions above are met: the export guard throws on an empty `imports`
list, the ported aspect takes no entity argument, and `nix-effects` is an explicit input.

**The tree is additive.** No file under `modules/slots/`, `modules/universal/` or `modules/meta/`
changed. `flake.nix` gained two inputs and one `imports` line, because a flake input cannot live
anywhere else. `flake.lock` gained exactly two nodes — den declares no flake input of its own.

| Piece | Path | Note |
|---|---|---|
| Loader and the four outputs | `modules/den/flake-module.nix` | A nested `lib.evalModules`, not a flake-parts module. |
| `devenv` class | `modules/den/classes/devenv.nix` | den ships none. 13 of 18 slots need it. |
| First aspect | `modules/den/aspects/rosetta-builder.nix` | Core options only. The guest-size options stay in the slot. |
| First devenv aspect | `modules/den/aspects/gh.nix` | A full port of `modules/slots/gh/`. |
| Parallel entities | `checks/den-mvp/{host-darwin,host-nixos,devenv}/` | They evaluate and build. None activates. |
| Build gate | `checks.<system>.den-mvp` | The current architecture. `.all` covers every system. |

**The entities live at `checks/den-mvp/`, not in `hosts/`.** They build and never activate, so they
are test artifacts, and `checks/` states that in the path. `hosts/` is wrong for a second reason:
every entry `flake.hostConfigurations` keeps goes through `modules/meta`, and den replaces that
pre-pass. A den host that inherits `modules/meta` proves nothing. See
[checks/den-mvp/README.md](../../../../checks/den-mvp/README.md).

Seven commands verify the milestone. Each one passed:

```bash
nix eval --json '.#denModules.rosetta-builder' --apply 'm: builtins.length m.imports'
nix eval --json '.#denModules.gh' --apply 'm: builtins.length m.imports'
nix eval --raw '.#denConfigurations.host-darwin.config.system.build.toplevel.drvPath'
nix eval --raw '.#denConfigurations.host-nixos.config.system.build.toplevel.drvPath'
nix eval --json '.#denDevenvShells' --apply builtins.attrNames
nix build  '.#checks.aarch64-darwin.den-mvp'
nix eval --json '.#hostConfigurations' --apply builtins.attrNames     # no den entity present
```

**The first slot-against-den comparison ran, and it agrees.** `anji` against `host-darwin`:
`config.nix-rosetta-builder` is identical, and so is
`config.nix.settings.builders-use-substitutes`. `config.nix.buildMachines` differs, because `anji`
also gets personal remote builders from `modules/universal/profile/remote-builders/`. den ports none
of that tree, so that difference is expected.

**Three facts the milestone measured**, each one a trap for the next milestone:

1. `den.flakeModule` declares **no** `flake.<output>` option. Each output name needs its own
   declaration. den ships `inputs.den.flakeOutputs.<name>` for the names it knows. A custom class
   output such as `devenvShells` needs a hand-written `lib.mkOption`.
2. den calls `instantiate { modules = [ … ]; }` and never passes `system`. Its darwin default is
   `inputs.darwin.lib.darwinSystem`, and this repo names that input `nix-darwin`. So the host
   overrides `instantiate` instead of an input alias.
3. A bare nix-darwin host needs `system.primaryUser` and `system.stateVersion`.
   `modules/universal` supplies neither on its own.
4. A build-only NixOS host needs a root `fileSystems."/"` (a `tmpfs` names no hardware),
   `boot.loader.grub.enable = false` (GRUB is on by default and then asserts a non-empty `devices`),
   and `system.stateVersion`.

**Criterion 2 passes, and den also runs as a plain library.** `den.nixModule inputs` is a second
entry point. It imports four files and exposes exactly `{ aspects, lib, policies }` — no
`den.hosts`, no `den.schema`, no `den.classes` and no `den.default`. `den.flakeModule` is what
imports all of den's `modules/` tree, and the batteries live there. `den.lib.aspects.resolve
"<class>" <aspect>` takes an arbitrary class name and needs no entity. den's own CI asserts the
shape in `templates/ci/modules/internal-api/den-as-lib.nix`.

Measured on 2026-09-10, for both ported aspects, the library route and the `flakeModule` route give
one **identical** `drvPath`:

| aspect | class | library-mode result | identical `drvPath` |
|---|---|---|---|
| `gh` | `devenv` | `gh-2.100.0` in the shell, `claude.code.enable = true` | yes |
| `rosetta-builder` | `darwin` | `nix.buildMachines` carries `aarch64-linux x86_64-linux` | yes |

The `rosetta-builder` test used a bare `nix-darwin.lib.darwinSystem` with no `modules/universal`, no
`mkSlots` and no `kdnConfig` — the real adopter shape. Three limits hold: the consumer must pass
`specialArgs.inputs` itself; library mode covers aspects and not entities, because `den.schema.host`
is absent; and two simple aspects are not a full sample.

**Library mode now ships as `flake.denLib`.** `modules/den/lib.nix` holds it, and it owns the aspect
registry too, so the library route and the `flakeModule` route read one list. The thin wrapper is
one call, and it drops straight into any target module:

```nix
imports = inputs.nix-configs.denLib.imports { class = "devenv"; aspects = [ "gh" ]; };
```

The raw machinery sits beside it — `nixModule`, `eval`, `resolve` and `aspectModules`. This
repository's own entities keep the `den.flakeModule` route, because entity resolution needs it.

Two guards protect the wrapper, both measured on 2026-09-10. An unknown aspect name throws when the
caller builds the list, not later when the module system forces one element. And a **whole-aspect**
function — `{ host, ... }: { name = …; devenv = …; }` — resolves to `{ imports = [ ]; }`, so
`resolve` throws. This sharpens condition 2 above: a **per-target** function
(`devenv = { host, ... }: …`) resolves non-empty, and it then fails inside the caller's own
evaluation with `attribute 'host' missing`. So the guard catches the first shape only.

**Two failures closed, and their root causes are separate.**

1. A den host with `class = "devenv"` fails with `The option 'nixpkgs' does not exist. Definition
   values: - In 'devenv@insecure-predicate/os'`. den always includes its `insecure-predicate` aspect
   through `den.default.includes`, and the aspect injects `${host.class}.imports` with an OS-shaped
   module that sets `config.nixpkgs`. A host whose class is not an OS class then breaks. A bare
   `resolve` never reads `den.default`, so the standalone shells declare no entity at all.
2. `kdn.den.devenv.root` cannot hold a store path. devenv's `claude.code` integration writes
   `files."${devenv.root}/.claude/settings.json"`, which makes the root a **dynamic attribute
   name**, and Nix rejects such a name when it refers to a store path
   (`<devenv>/src/modules/integrations/claude.nix:977`). The option now defaults to `/den-mvp`.

**Pattern V1 fails for the slot route, and it works for every den output.** `flake.nix:250` sets
`nix-configs = self`, so the whole tree hash enters every `modules/universal`-derived derivation and
a new file changes every `drvPath` there. A den evaluation never reads `self`. Measured on
2026-09-10: `denConfigurations.host-darwin` kept the byte-identical `drvPath`
`7zhp7889kchljri5j7phaakfvzv9j3ph-darwin-system-26.11.4cff07d.drv` across a file move, a second host
and a rename. `denDevenvShells.devenv-darwin` kept
`k7iqgp8lv0qk2qp3vqkxii8m4gg8g7v3-devenv-darwin.drv` across a perturbation of an unrelated tracked
file. Removal of the `"${self}"` root extended the gate from `denConfigurations` to all four
outputs.

**The MVP now tests itself, in three tiers.** `checks/den-mvp/tests.nix` holds them, and
`checks/default.nix` merges them into `checks.<system>`. Tier 1 compares evaluated option values.
Tier 2 greps the built nix-darwin toplevel — nix-darwin's own `release.nix` pattern. Tier 3 runs
each devenv shell's `config.test`. **No tier activates anything**, and none needs sudo: tier 2 reads
a store path and never runs it, and tier 3 uses `enterTest`, which devenv keeps separate from
`enterShell`. `nix run '.#checks.aarch64-darwin.den-mvp.smoke'` builds every check and prints one
summary — **11 of 11 pass on 2026-09-10**. The `gh` and `devenv-cli` aspects carry their own
offline assertions, so they travel with the aspect to an external adopter.

`den-eval-routes` turns the hand-measured `drvPath` claim above into a test, so the library route
and the `flakeModule` route cannot drift apart in silence.

One trap the harness found: a den devenv shell must pin `devenv.cli.version`. A null value makes
devenv's `tasks` module prepend `devenv-tasks run devenv:enterTest` to `enterTest`
(`<devenv>/src/modules/tasks.nix:486`), and that binary needs a writable `devenv.dotfile` plus a
task source. A build sandbox gives it neither, so a smoke test fails with `Error: NoSource`.
`config.devenv.latestVersion` is the right value, and it also silences the version-mismatch warning.

**A four-target aspect closes the full-matrix gap.** No slot in this repository targets all four
kinds; the widest is `modules/slots/devenv/`, at three (`nixos`, `darwin`, `home`). So
`modules/den/aspects/devenv-cli.nix` ports that slot and **adds** a `devenv` target the slot has
none of. It is now the only aspect that reaches every den class the harness covers, and
`den-eval-devenv-cli` asserts 12 values across all four.

Reaching the `homeManager` class needed a den **user**, not a home-manager import.
`<den>/modules/aspects/batteries/home-manager.nix` imports
`inputs.home-manager.<class>Modules.home-manager` into the host by itself and forwards each user's
`homeManager` config to `home-manager.users.<userName>`. `checks/den-mvp/users/` holds the one shared
`dev` user. Two traps came out of that work, and neither gives an error:

1. A user's `classes` defaults to `[ "user" ]`, with **no** `homeManager`
   (`<den>/nix/lib/entities/host.nix:157`). A user that omits it silently gets no home-manager
   generation, and the `homeManager` half of every aspect it includes goes nowhere.
2. **den partitions an aspect by scope.** A four-target aspect must be included **twice** on a host:
   once in the host aspect for `nixos`/`darwin`/`devenv`, once in the user aspect for `homeManager`.
   Measured on 2026-09-10: host scope alone gave **0** devenv in
   `home-manager.users.dev.home.packages`; both scopes gave **1**.

`denModules.<aspect>` cannot carry `devenv-cli`. That zero-argument form names one common class per
aspect, and this one has four. `denLib.imports` is the general form, and the test asserts it resolves
one module on each class.

`checks/den-mvp/home/` adds the standalone home-manager route beside the host route. The two answer
different questions. The standalone route asks whether an aspect's `homeManager` half is a valid
home-manager module on its own — the shape an external adopter uses. The host route asks whether den
forwards that half into a real system, and only it can hit trap 2 above.

One test kind stays deferred, for a stated reason. An automated `hosts/anji`-against-`host-darwin`
parity check evaluates a whole personal host (about 93 s) and reads sops metadata. A `runNixOSTest`
VM test is no longer blocked — `host-nixos` carries a real `nixos`-class aspect now — but it still
earns nothing: every value a guest would read is a static option value or a file in the toplevel,
and tier 1 and tier 2 read both. A VM pays off only for a runtime behaviour.

The adopter-facing library-mode export is done. The `home` target and the first `nixos`-class
aspect are both done, through `devenv-cli`.

## Milestone 2 covers every slot — scope decision, 2026-09-10

The user set the target: **reimplement all of `modules/slots/` as den aspects.** A representative
sample is not the goal. The earlier plan named one coupled pair (`jj` plus `mcp`); that pair is now
one step in a full port.

`modules/slots/` holds 18 slots plus a 22-line loader, and 4,160 lines of Nix and shell. Three
slots are ported:

| Slot | LOC | State |
|---|---|---|
| `gh` | 53 | full port — `modules/den/aspects/gh.nix` |
| `devenv` | 61 | full port, plus a `devenv` target the slot has none of — `modules/den/aspects/devenv-cli.nix` |
| `rosetta-builder` | 180 | core options only. The guest-size options stay in the slot. |

Fifteen slots remain, at about **3,866 lines**. The order below groups them by the den mechanism
each one needs, and it puts the cheap tests first:

| Order | Slot or family | LOC | Slot targets | What it tests |
|---|---|---|---|---|
| 1 | `ssh-agent` | 76 | `home` | **Done.** The user scope alone. No host target at all. |
| 2 | `ca` | 91 | `nixos` | **Done.** The first `nixos`-only aspect. The option lives inside the `nixos` target. |
| 3 | `nix` | 148 | `devenv` | A slot that reads repository content through `${inputs.nix-configs}`. |
| 4 | `opencode` | 197 | `devenv` | Personal defaults inside a shared option — it overlaps 004 of the plan. |
| 5 | `zellij` | 221 | `devenv` | A slot that ships an agent rule and a skill. |
| 6 | `mcp` family — `mcp`, `snoop`, `pretty-print`, `basic-memory` | 646 | `devenv` | **Slot-to-slot option coupling.** The first hard case. |
| 7 | `jj` family — `jj`, `jj/fork` | 949 | `devenv` | The second coupled pair, and the largest shell payload. |
| 8 | `llm` family — `llm`, `llm/client`, `llm/proxy` | 1,287 | `nixos`, `devenv` | One family that spans two classes. |
| 9 | `ssh-access` | 251 | `devenv`, `home` | **Blocked on 009.** It carries personal data. |

### Three obstacles the inventory names

Each one is read from the source, and none of them is solved yet.

1. **Slot-to-slot option coupling.** `modules/slots/mcp/snoop/default.nix:22-23` reads
   `config.kdn.mcp.enable` and writes `kdn.mcp.commandOverlays`. So one slot configures another
   slot's option. den partitions an aspect by class and by scope, so a shared option needs one
   owner and one evaluation. Order 6 above is the first test of this, and it is the reason the
   earlier plan named a coupled pair.
2. **A slot writes a target option flat.** `modules/slots/mcp/snoop/default.nix:34` sets
   `devenv.packages` with no target wrapper. The slot loader accepts that. den needs the value
   inside a class target, so each such site needs a rewrite.
3. **`ssh-access` holds personal data.** `modules/slots/ssh-access/kdn-graph.nix` carries hosts,
   LAN addresses and zones. It moves to the personal folder of
   [009](../009-personal-data-folder/definition.md) first, so order 9 waits for that checkpoint.

### What needs no new den mechanism

The four-class matrix is proven — `den-eval-devenv-cli` asserts 12 values across `nixos`, `darwin`,
`devenv` and `homeManager`. So orders 1 to 5 need port work only, not den research. Note the name
change: a slot calls the target `home`, and den calls the class `homeManager`.

The README status table tracks each row.

## Why this comes first

If den wins, this repo throws away the work to reimplement modules onto slots. If den loses, the
spike cost is one bounded experiment. So the spike runs before the reimplementation, not after.

den looks less abstract than the alternatives in that space, and a better match to this repo's
problems. That impression needs a test, not agreement.

## Where the spike lives

`modules/den/`, parallel to and independent of `modules/slots/`. Reimplement representative slots
as aspects. **Do not remove or modify `modules/slots/`.**

Pick the representative set deliberately: one devenv-only slot, one that targets `darwin`, one that
targets `home`, and one with cross-slot coupling. `rosetta-builder` is the obvious `darwin` choice.
`jj` couples to `kdn.mcp.*`.

## Success criteria, in order of importance

### Criterion 2 is decisive — test it first

> **Can an external adopter import a resolved den aspect as a plain drop-in module, and not adopt
> den in their own repo?**

This is the whole point. The creator wants an imported drop-in.

What is already known:

- `den.lib.aspects.resolve "<class>" <aspect>` returns a plain module, and it is CI-tested in den's
  own `templates/ci/modules/internal-api/den-as-lib.nix`.
- **But `reference/lib.mdx` labels it "Internal". `guides/debug.md` explicitly warns against
  production use.**
- There is no documented supported route to export aspects as `nixosModules`/`homeModules`. Zero
  doc mentions.
- The repo that produces the aspect must still be a den repo.

So the mechanism exists, and this repo does not trust it. Establish three things. Does it work for
this repo's real cases? Is the Internal label a stability warning or a correctness warning? Will
the maintainers commit to it? den's discussion #569 asks a closely related question, and stays
unanswered since 2026-05-24. Ask there, or open a new question.

**If criterion 2 fails, den does not deliver the goal.** Say so plainly and stop.

**Answered — PASS, with two limits.** See the phase 1 verdict above, and
[research.md](research.md) for the seven cases and the two verified workarounds.

### Criterion 1 — can a `devenv` class exist at all

den has **no** devenv class. Zero mentions in its docs, code, issues, or discussions.
`den.classes` declares only `nixos` and `darwin`; `homeManager`, `hjem`, `maid`, `wsl`,
`flake-parts`, `os`, and `user` come from batteries.

The nearest template, `templates/flake-parts-modules/modules/classes/devshell.nix`, wires
**numtide/devshell, not cachix/devenv**. A devenv class looks like ~15 lines that copy it. But that
rests on one **unverified** point: devenv must be reachable as a flake-parts module or an
`evalModules` target.

13 of 20 slots target devenv. So a failure here is close to fatal.

**Answered — PASS.** devenv is a plain `lib.evalModules` target: `<src>/src/modules/top-level.nix`,
with mandatory `specialArgs.inputs` (it may be `{ }`), `_module.args.pkgs`, `devenv.root`,
`devenv.tmpdir`, and the shell at `config.shell`. It needs no `--impure`, no CLI, and no
CppNix-only builtin. A ~30-line `den.classes.devenv` produced real derivation paths on three
routes, and den's own `policy.instantiate` route gives a bit-identical `drvPath` on `main` and on
v0.18.0. `SPIKE_HOST=igloo` proved entity data reaches a devenv aspect.

**Correction to the sketch above:** copy `templates/terranix-demo/modules/terranix.nix`, which uses
`policy.instantiate`. Do not copy `devshell.nix` — devenv is a separate `evalModules` universe, not
a flake-parts module.

### Criterion 3 — does den satisfy the conditional-imports requirement

Checkpoint 005 writes that requirement down as a testable statement. Test den against it here.

Known constraint: den's resolution runs **before** `evalModules`, with function-argument-shape
introspection plus `nix-effects`. That solves imports that depend on entity or context **data**. It
does not obviously solve imports that depend on module **config**. Establish which kind this repo's
requirement needs — 005 answers that.

### Criterion 4 — does the 1→N mixed-aspect collision still reproduce

A third-party evaluation against about v0.15 documented one collision. A mixed aspect holds both
`nixos` and `homeManager` keys. On a host with two users, it defines the host-level config twice:

```
The option 'boot.kernelPackages' is defined multiple times
```

The documented workaround splits every mixed aspect into host and user halves. The author says that
defeats the point of aspect-oriented configuration. den's PR #609 fixed a related leak. v0.16
through v0.18 changed `entity.aspect` semantics, so this may be stale. **Re-test on current den.**

**Answered — REFUTED.** `boot.kernelPackages` resolves to one value on both revisions, with one
mixed aspect included by two `homeManager` users. The collision message stays reachable for a
genuine two-aspect conflict, and it now carries useful `nixos@<aspect>` labels. One side finding to
keep: a **host**-scope mixed aspect's `homeManager` half never reaches
`home-manager.users.<user>`. That is den's scope partitioning, and `den.batteries.forward` is the
bridge.

## Risks to record in the outcome

- den is v0.x with **no stable API**. v0.16 changed `entity.aspect` semantics. v0.18 scoped the
  entity-arg binding. Both are breaks. Wholesale renames: `den.ctx` → `den.schema`,
  `den.provides`/`den._` → `den.batteries`, `meta.adapter` → `meta.handleWith`. There is a whole
  `lib-deprecated.mdx` page. No patch release has ever shipped.
- `main` carries about 2.5 months of unreleased drift past v0.18.0 (2026-06-23).
- 31 contributors, but **2 people are about 90% of commits**.
- The core rests on `denful/nix-effects` — 2 stars, single author — despite "zero dependencies"
  marketing.
- den needs neither flakes nor flake-parts. `templates/noflake` uses npins plus `lib.evalModules`.
  `den.nixModule` works in any `evalModules`. That is genuinely good for this repo.

## Kill criterion

Stop and record a negative outcome if **criterion 2 fails**, or if you cannot meet **criterion 1**.

State the central tension in the outcome either way:

> den's strongest claim would improve the creator's own ergonomics. That is not the same as support
> for external adoption. Only criterion 2 decides the second question.

## Deliverable

A `.done.md` sibling with a verdict per criterion. Tag each verdict confirmed or unverified, with
the evidence. Then feed it into 006.

Note that 003's plain-import boundary is framework-agnostic. Whichever way this goes, an adopter's
entry point should not require them to learn the creator's framework choice.
