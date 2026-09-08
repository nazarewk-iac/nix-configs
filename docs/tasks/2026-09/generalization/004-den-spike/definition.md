---
type: Task
description: Evaluate the denful/den framework as the reimplementation target before any module rewrite starts, with a drop-in import test as the decisive criterion.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 004 — den spike

Hub: [../generalization-plan.md](../definition.md). **Run this as early as possible.**
Together with 005 it gates 006.

Goal: decide whether `denful/den` can be the target framework, before any module is rewritten.

## Why this comes first

If den wins, work done to reimplement modules onto slots is thrown away. If den loses, the spike
cost is one bounded experiment. So the spike runs before the reimplementation, not after.

den looks less abstract and better matched to this repo's problems than the alternatives in that
space. That impression needs a test, not agreement.

## Where the spike lives

`modules/den/`, parallel to and independent of `modules/slots/`. Reimplement representative slots
as aspects. **Do not remove or modify `modules/slots/`.**

Pick the representative set deliberately: one devenv-only slot, one that targets `darwin`
(`rosetta-builder` is the obvious choice), one that targets `home`, and one with cross-slot
coupling (`jj` couples to `kdn.mcp.*`).

## Success criteria, in order of importance

### Criterion 2 is decisive — test it first

> **Can an external adopter import a resolved den aspect as a plain drop-in module, without
> adopting den in their own repo?**

This is the whole point. The creator wants an imported drop-in.

What is already known:

- `den.lib.aspects.resolve "<class>" <aspect>` returns a plain module, and it is CI-tested in den's
  own `templates/ci/modules/internal-api/den-as-lib.nix`.
- **But it is labelled "Internal" in `reference/lib.mdx`, and explicitly warned against for
  production use in `guides/debug.md`.**
- There is no documented supported route to export aspects as `nixosModules`/`homeModules`. Zero
  doc mentions.
- The producing repo must still be a den repo.

So the mechanism exists and is untrusted. Establish: does it work for this repo's real cases; is
the Internal label a stability warning or a correctness warning; and will the maintainers commit to
it. den's discussion #569 asks a closely related question and has been unanswered since
2026-05-24 — ask there, or open a new question.

**If criterion 2 fails, den does not deliver the goal.** Say so plainly and stop.

### Criterion 1 — can a `devenv` class exist at all

den has **no** devenv class. Zero mentions in its docs, code, issues, or discussions.
`den.classes` declares only `nixos` and `darwin`; `homeManager`, `hjem`, `maid`, `wsl`,
`flake-parts`, `os`, and `user` come from batteries.

The nearest template, `templates/flake-parts-modules/modules/classes/devshell.nix`, wires
**numtide/devshell, not cachix/devenv**. A devenv class looks like ~15 lines copying it, but that
rests on devenv being reachable as a flake-parts module or an `evalModules` target, which is
**unverified**.

13 of 20 slots target devenv. So a failure here is close to fatal.

### Criterion 3 — does den satisfy the conditional-imports requirement

Checkpoint 005 writes that requirement down as a testable statement. Test den against it here.

Known constraint: den's resolution runs **before** `evalModules`, using function-argument-shape
introspection plus `nix-effects`. That solves imports that depend on entity or context **data**.
It does not obviously solve imports that depend on module **config**. Establish which kind this
repo's requirement actually needs — 005 answers that.

### Criterion 4 — does the 1→N mixed-aspect collision still reproduce

A third-party evaluation against about v0.15 documented that a mixed aspect — one with both
`nixos` and `homeManager` keys — applied to a host with two users makes the host-level config get
defined twice:

```
The option 'boot.kernelPackages' is defined multiple times
```

The documented workaround is to split every mixed aspect into host and user halves, which the
author says defeats the point of aspect-oriented configuration. den's PR #609 fixed a related
leak, and v0.16 through v0.18 changed `entity.aspect` semantics, so this may be stale.
**Re-test on current den.**

## Risks to record in the outcome

- den is v0.x with **no stable API**. Breaking changes in v0.16 (`entity.aspect` semantics) and
  v0.18 (entity-arg binding scoped). Wholesale renames: `den.ctx` → `den.schema`,
  `den.provides`/`den._` → `den.batteries`, `meta.adapter` → `meta.handleWith`. There is a whole
  `lib-deprecated.mdx` page. No patch release has ever shipped.
- `main` carries about 2.5 months of unreleased drift past v0.18.0 (2026-06-23).
- 31 contributors, but **2 people are about 90% of commits**.
- The core rests on `denful/nix-effects` — 2 stars, single author — despite "zero dependencies"
  marketing.
- den needs neither flakes nor flake-parts (`templates/noflake` uses npins plus
  `lib.evalModules`), and `den.nixModule` works in any `evalModules`. That is genuinely good for
  this repo.

## Kill criterion

Stop and record a negative outcome if **criterion 2 fails**, or if **criterion 1 cannot be met**.

State the central tension in the outcome either way:

> den's strongest claim would improve the creator's own ergonomics. That is not the same as
> enabling external adoption. Only criterion 2 decides the second question.

## Deliverable

A `.done.md` sibling with a verdict per criterion, each tagged confirmed or unverified with the
evidence. Then feed it into 006.

Note that 003's plain-import boundary is framework-agnostic. Whichever way this goes, an adopter's
entry point should not require them to learn the creator's framework choice.
