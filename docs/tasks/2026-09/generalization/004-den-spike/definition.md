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
| Parallel host | `modules/den/entities/den-darwin.nix` | It evaluates and builds. It never activates. |

**A den host must not live in `hosts/`.** `flake.hostConfigurations` reads that directory from a
listing and sends every entry through `modules/meta`. den replaces that pre-pass, so a den host
under `hosts/` proves nothing.

Four commands verify the milestone. Each one passed:

```bash
nix eval --json '.#denModules.rosetta-builder' --apply 'm: builtins.length m.imports'
nix eval --raw '.#denConfigurations.den-darwin.config.system.build.toplevel.drvPath'
nix eval --raw '.#denDevenvShells.den-darwin.shell.drvPath'
nix eval --json '.#darwinConfigurations' --apply builtins.attrNames   # unchanged
```

**Three facts the milestone measured**, each one a trap for the next milestone:

1. `den.flakeModule` declares **no** `flake.<output>` option. Each output name needs its own
   declaration. den ships `inputs.den.flakeOutputs.<name>` for the names it knows. A custom class
   output such as `devenvShells` needs a hand-written `lib.mkOption`.
2. den calls `instantiate { modules = [ … ]; }` and never passes `system`. Its darwin default is
   `inputs.darwin.lib.darwinSystem`, and this repo names that input `nix-darwin`. So the host
   overrides `instantiate` instead of an input alias.
3. A bare nix-darwin host needs `system.primaryUser` and `system.stateVersion`.
   `modules/universal` supplies neither on its own.

**Pattern V1 does not apply to this tree.** `flake.nix` sets `nix-configs = self`, so the whole
tree hash enters every derivation. A new file changes every `drvPath`. This milestone proved
additivity by output **names** instead: `darwinConfigurations` still lists the same hosts.

Milestone 2 owns the next three pieces: a `home` target, one devenv-only slot, and the coupled
`jj`+`mcp` pair. The README status table tracks them.

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
