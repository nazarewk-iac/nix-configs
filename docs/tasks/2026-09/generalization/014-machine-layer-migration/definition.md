---
type: Task
status: open
description: Migrate the machine layer — modules/universal and modules/meta — onto the chosen target framework, in measured batches.
timestamp: 2026-09-11T12:00:00+02:00
authored_by: agent
---

# 014 — machine layer migration

Hub: [../definition.md](../definition.md).

Goal: move the **machine layer** onto the target framework, so an **external adopter** imports a
module and passes nothing else. The machine layer is `modules/universal/` plus `modules/meta/`.

Task [004](../004-den-spike/definition.md) covers `modules/slots/` only. No other task covers the
machine layer. This task closes that gap.

## Why this task exists

The gap is measured, not an impression. Four tasks each touch the machine layer and each rules
itself out of migrating it:

- `004-den-spike` scopes itself to `modules/slots/`.
- `006-direction-decision` reserves the answer as unwritten output — "the pieces of
  `modules/universal` to reimplement, and the ones to drop" — and stays `open`.
- `012-darwin-host-clone` maps capabilities onto aspects, then states that `modules/slots/`,
  `modules/universal/` and `modules/meta/` stay untouched.
- `009-personal-data-folder` records intent only: keep the files where they are for now, and log
  where each one is expected to go.

So the machine layer had no owner. This task is the owner.

## The gate — three things must land first

This task **executes nothing** until all three are true. Check each one before you start.

| Gate | Task | Why it blocks |
|---|---|---|
| The conditional-imports requirement is written and testable | [005](../005-conditional-imports-requirement/definition.md) | `modules/meta` exists to let **data** drive conditional imports of third-party modules. A plain `evalModules` hits infinite recursion. A target framework that cannot do this cannot host the machine layer. |
| The target framework is chosen | [006](../006-direction-decision/definition.md) | Migrating twice is the one waste this plan exists to prevent. |
| Personal data is out of the modules | [009](../009-personal-data-folder/definition.md) | A migrated module that still carries the creator's values gives an adopter nothing. Migration would move the data, not remove it. |

Two parts of this task **are** unblocked, and they are step 1 and step 2 below: the per-area audit
and the batch order. Both are inventory work. Neither edits a module.

## The measured obstacle

Migration is a rewrite of how a module reaches its context, not a file move. Three numbers say why.
All are measured on 2026-09-11.

| Fact | Value |
|---|---|
| Size | 192 `.nix` files, about 20,220 lines |
| Declared `kdn.*` option prefixes | 169 |
| `kdnConfig` references | **561, across 183 of the 192 files** |
| `kdn.env.*` references | 150, across 105 files |
| `kdn.profile.*` references | 62, across 17 files |
| Host consumers | 16 |

94% of the files take the `kdnConfig` special argument. A drop-in module may take none.

### The guards are not the obstacle

`kdnConfig.util.*` has 329 call sites. 292 of them are pure class dispatch:

| Guard | Sites | Replaceable by a class? |
|---|---|---|
| `ifTypes` | 162 | yes |
| `ifHMParent` | 58 | yes |
| `ifHM` | 57 | yes |
| `ifNotHMParent` | 9 | yes |
| `isOfType` | 6 | yes |
| `hasParentOfAnyType` | 30 | **no — it reads the parent chain** |
| `modules` / `loadModules` | 5 | **no — it is the loader itself** |
| `hasSops` | 2 | **no — it reads discovered secret state** |

So 89% of the guard sites map onto a class mechanism. **37 sites do not**, and those 37 hold the
real design work. Address them first, in step 3, and the rest becomes mechanical.

### The coupling is the obstacle

The tree is valuable *because* modules set each other's options. `kdn.env.*` alone has 150
references across 105 files. `.agents/rules/slots-standalone.md` forbids exactly that coupling for
a standalone module. So a naive conversion either breaks that rule or re-invents
`modules/universal` under a new name.

This task must state, in its solution, how the target framework expresses intra-tree coupling. That
answer is a prerequisite for every batch after the first.

## The three routes

Record the choice with evidence. Do not assume route 2.

| Route | What it means | Cost | Adopter gain |
|---|---|---|---|
| 1. Plain-module exports | Keep the tree. Export per-area plain modules, plus one wrapper that builds `kdnConfig` internally so an adopter never sees it. | days | an adopter imports one area; the plumbing hides |
| 2. Full migration | Every area becomes an aspect. Delete `kdnConfig`. | months | full parity with the tooling layer |
| 3. Leave it | The tooling layer ships. The machine layer stays creator-only. | zero | none for the machine layer |

**Route 1 is the recommended first step under either of the other two.** It is
framework-agnostic, so it is not wasted work whatever `006` decides. Route 2 remains possible on
top of route 1's boundary.

Record the risk honestly when route 2 goes to the creator: the candidate framework is a v0.x
project with no stable API, it had breaking changes across recent minor versions, its resolve entry
point is documented as internal, and two people write about 90% of its commits. That is an
acceptable bet for 20 tooling aspects pinned by a check suite. It is a much larger bet for 20,220
lines of machine configuration.

## The batch inventory

Migrate by area. The order below sorts by risk, not by size: an area with few `kdnConfig`
references and few option prefixes migrates first and proves the pattern.

| Area | Files | Lines | `kdnConfig` | Option prefixes | Batch |
|---|---|---|---|---|---|
| `nix` | 1 | 104 | 0 | 1 | 1 — pilot |
| `outputs` | 1 | 27 | 1 | 1 | 1 |
| `helpers` | 1 | 79 | 2 | 1 | 1 |
| `monitoring` | 1 | 97 | 2 | 1 | 1 |
| `emulation` | 1 | 52 | 3 | 1 | 1 |
| `managed` | 1 | 158 | 3 | 1 | 1 |
| `apps` | 1 | 163 | 5 | 1 | 2 |
| `disks` | 2 | 1236 | 5 | 1 | 2 |
| `env` | 1 | 73 | 4 | 2 | 2 — **coupling root** |
| `locale` | 1 | 150 | 5 | 1 | 2 |
| `packaging` | 1 | 52 | 4 | 1 | 2 |
| `headless` | 1 | 280 | 6 | 1 | 2 |
| `fs` | 3 | 378 | 7 | 3 | 3 |
| `security` | 6 | 605 | 15 | 5 | 3 |
| `networking` | 8 | 2863 | 16 | 9 | 3 |
| `virtualisation` | 10 | 620 | 32 | 10 | 4 |
| `toolset` | 12 | 605 | 34 | 12 | 4 |
| `hw` | 17 | 1079 | 34 | 11 | 4 |
| `desktop` | 17 | 2349 | 37 | 8 | 4 |
| `services` | 14 | 1206 | 38 | 13 | 5 |
| `profile` | 16 | 2861 | 73 | 15 | 5 — **hardest** |
| `development` | 30 | 1703 | 74 | 30 | 5 |
| `programs` | 40 | 2781 | 129 | 40 | 5 |
| root files | 6 | 699 | — | 3 | 6 — the loader, last |

Counts exclude machine-local additions that are not part of the shared tree.

Three notes the table does not show:

- **`env` is the coupling root.** 105 files write `kdn.env.*`. Migrate `env` in batch 2, and settle
  the coupling answer there, before any large area.
- **`profile` is the hardest area, not the largest.** It holds both `009` hard blockers, and it sets
  105 enables across other areas.
- **The root files are the loader.** `modules/universal/default.nix` recursively loads every
  `**/default.nix` and injects the Home Manager shared modules. It migrates last, because every
  batch before it still needs it.

## The steps

1. **Per-area audit.** For each area, record: the option prefixes it declares, the option prefixes
   it reads from other areas, the third-party modules it imports conditionally, and any personal
   value still in it. Unblocked today.
2. **Fix the batch order** from that audit. The table above is a starting point from file counts
   only. Unblocked today.
3. **Design the replacement for the 37 non-class guard sites** — `hasParentOfAnyType`,
   the loader, and `hasSops`. Gated on `006`.
4. **Migrate batch 1 as a pilot.** One batch, one commit chain, and a written pattern that batch 2
   copies. Gated on all three gates.
5. **Migrate batches 2 to 6 in order.** Each batch keeps the old path working — the change is
   **additive** until the creator decides to retire the old tree.
6. **Retire, or do not.** Retirement is the creator's decision, never this task's.

## Verification

Every batch meets all four:

- **Behaviour is preserved.** An option-value probe of the derived values, on the pristine parent
  and on the new tree, over all 16 host configurations. The values must match. A `drvPath` equality
  proof does **not** work in this repository: `kdnConfig` reaches evaluated config, so any edit
  moves every host path. Probe values, not paths.
- **The drop-in holds.** The migrated area evaluates from a directory outside this repository, with
  no `specialArgs`, no `kdnConfig`, no overlay and no custom module argument.
- **The adopter-hostile eval passes.** It evaluates with no SSH agent and with the personal data
  folder absent.
- **One host builds.** Not a switch. The creator runs any activation.

## Out of scope

- A rename of the `kdn.*` namespace.
- A retrofit of `modules/universal` into `modules/slots`. The hub rules that out.
- Retirement of `modules/universal` or `modules/meta`. Step 6 states the decision is the creator's.
- Any push.

## Exit criteria

1. The per-area audit exists, and step 2 has fixed the batch order.
2. The route choice is recorded with evidence, and the creator has agreed to it.
3. The 37 non-class guard sites have a designed replacement.
4. Every batch in the agreed route is migrated, and each one passes all four verification items.
5. A sibling `done.md` states the root cause, the solution, the verification steps and the
   follow-up notes.
