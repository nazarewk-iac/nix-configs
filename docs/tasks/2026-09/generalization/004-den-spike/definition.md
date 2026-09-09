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

Goal: decide whether `denful/den` can be the target framework, before anybody rewrites a module.

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

### Criterion 1 — can a `devenv` class exist at all

den has **no** devenv class. Zero mentions in its docs, code, issues, or discussions.
`den.classes` declares only `nixos` and `darwin`; `homeManager`, `hjem`, `maid`, `wsl`,
`flake-parts`, `os`, and `user` come from batteries.

The nearest template, `templates/flake-parts-modules/modules/classes/devshell.nix`, wires
**numtide/devshell, not cachix/devenv**. A devenv class looks like ~15 lines that copy it. But that
rests on one **unverified** point: devenv must be reachable as a flake-parts module or an
`evalModules` target.

13 of 20 slots target devenv. So a failure here is close to fatal.

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
