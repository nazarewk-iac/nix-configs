---
type: Task
description: Choose slots or den as the single reimplementation target, on the evidence from the den spike and the conditional-imports requirement.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 006 — direction decision: slots or den

Hub: [../generalization-plan.md](../definition.md). Gated on
[004](../004-den-spike/definition.md) and
[005](../005-conditional-imports-requirement/definition.md).

Goal: pick **one** target for the reimplementation of the relevant pieces of `modules/universal`.
Build the winner. Do not build the loser.

## The creator's stated preference — 2026-09-10

> "I would prefer the adopter to use the den config if the spike works out."

The spike worked out. 004 phase 1 answered criterion 2 **PASS**, criterion 1 **PASS**, and
criterion 4 **REFUTED**. So **den is the default choice for the adopter-facing configuration**, and
this task now carries the burden of proof against den, not for it.

Two things this preference does **not** settle:

1. **Criterion 3 stays open** until 005 states the conditional-imports requirement. A failure there
   is still a reason to pick slots.
2. **The adopter never adopts den.** The preference is that an adopter consumes a **den-resolved
   plain module**, which is exactly what criterion 2 measured. It is not that an adopter writes den
   aspects. See the constraint at the end of this file.

Record the risk plainly in the outcome: den's `den.lib.aspects.resolve` is labelled `Internal`, den
publishes no CHANGELOG, and discussion #569 is unanswered. `mkSlots` carries none of that risk. The
preference accepts it; it does not remove it.

## The two options

1. **Reimplement the relevant pieces onto slots.** Extend `lib/slots/schema.nix` with whatever the
   005 requirement needs, most likely a data-driven conditional-import mechanism.
2. **Reimplement the relevant pieces onto den.** Adopt `denful/den` as the framework, with the
   spike from 004 as the evidence.

## What is explicitly not an option

**A retrofit of `modules/universal` in place.** It does not make sense here, for two independent
reasons.

First, `.agents/rules/slots-standalone.md` forbids exactly the intra-tree option coupling that
makes the universal tree valuable. The measured coupling:

| Coupling | Reach |
|---|---|
| `kdn.env.packages` / `kdn.env.variables` | 108 files, 152 references, one declaration in `modules/universal/env/default.nix` |
| `kdn.security.secrets.sops.files` | 18 files, 50 references |
| `kdn.profile.*` | sets 105 distinct `kdn.*.enable` paths against 169 distinct `options.kdn.*` prefixes |
| `kdn.disks.persist` | across the disko/ZFS engine |

A conversion that honours the standalone rule loses this. A conversion that breaks the rule
re-invents `modules/universal` under a new name.

Second, `modules/meta` solves a real problem — see 005. A retrofit would have to reproduce it
anyway.

So the question is not how to convert the tree. The question is which framework receives the pieces
this repo keeps.

## Decision inputs

From [004](../004-den-spike/definition.md):

| Criterion | Weight |
|---|---|
| 2 — an adopter imports a resolved aspect as a plain drop-in, and does not adopt den | **decisive** |
| 1 — a `devenv` class can exist (13 of 20 slots target devenv) | near-fatal if it fails |
| 3 — den satisfies the 005 requirement | required |
| 4 — the 1→N mixed-aspect collision is gone | important, workaround exists |

From [005](../005-conditional-imports-requirement/definition.md): the conformance test, and the
confirmed answer to whether any `imports` list depends on evaluated `config` rather than static
data.

## How to decide

Score both options against the same list. Write the score down.

| Question | slots | den |
|---|---|---|
| Satisfies the 005 requirement | needs new mechanism — cost? | 004 criterion 3 |
| Adopter imports a drop-in with no need to learn the framework | already true — `mkSlots` is small | 004 criterion 2 |
| devenv support | native, 13 slots ship today | 004 criterion 1 |
| API stability | this repo owns it | v0.x, no stable API, 2 maintainers do 90% of commits |
| Maintenance burden | this repo carries it all | shared, but with upstream drift risk |
| Cost to reach parity for the pieces this repo keeps | — | — |

Two honest asymmetries to weigh, not to hide:

- **slots is a known quantity that this repo maintains alone.** Its schema is 72 LOC. An extension
  is cheap, and this repo fully controls it. But every future need is also this repo's own work.
- **den is a better-designed abstraction with real project risk.** v0.x, no patch release ever,
  about 2.5 months of unreleased drift on `main`, and a core that rests on a single-author
  dependency.

## Output

A `.done.md` sibling with:

1. the chosen direction, in one sentence;
2. the score table, with the evidence in it;
3. the pieces of `modules/universal` to reimplement, and the ones to drop;
4. a strangler-fig sequence for the winner — no big bang;
5. what happens to `modules/slots` if den wins, and to `modules/den/` if slots wins. Do not leave
   either tree half-migrated.

## Constraint on the outcome

Whatever wins, the adopter entry point must not force an adopter to learn the creator's framework
choice. That boundary is framework-agnostic. 001 and 002 establish it before this decision, on
purpose. So the decision cannot break it.
