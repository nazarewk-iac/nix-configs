---
type: Solution
description: An adopter runbook that goes from a stock Apple Silicon Mac to one built x86_64-linux derivation, with a caveats table built only from this repository's own history.
task: definition.md
authored_by: agent
timestamp: 2026-09-11T12:00:00Z
---

# 003 — the nix-darwin getting-started runbook, landed

Parent: [definition.md](definition.md).

## Root cause analysis

An external adopter had no entry document. Every Darwin instruction sat inside a host config or a
task note, so an adopter had to read this repository's own history to find the order of the steps.

A second cause made a naive guide risky. This repository's Darwin history mixes real, recorded
traps with generic nix-darwin folklore. A guide that repeats the folklore as fact wastes an
adopter's time on a problem that never happened here. The task named nine such claims and
demanded either evidence or an explicit unverified mark.

A third cause: this repository's `nixpkgs` input points at a personal fork
(`flake.nix:4`, with the adopter note at `flake.nix:7-13`). A runbook that leans on that fork
sends an adopter down a path only the creator can walk.

## Solution

`docs/nix-darwin-getting-started.md`, `type: How-To`, 444 lines. It takes one ordered path:
a stock Mac, then nix-darwin, then a Rosetta-backed Linux builder, then one `x86_64-linux` build.

| Section | Line | Content |
|---|---|---|
| the bootstrap dance | `:149` | the ordered install steps |
| the exit test | `:274` | the command that proves a cross-platform build |
| the caveats table | `:329` | 33 rows, each with a cause and a fix |
| unconfirmable traps | `:383` | the folklore, kept apart from the verified rows |
| known gaps | `:406` | what the runbook does not cover |
| time and disk | `:424` | the cost an adopter pays |

Each exit criterion:

1. **A reader builds an `x86_64-linux` derivation from the runbook alone.** The runbook holds its
   own exit test at `:274`. See the follow-up note — an external reader has not run it.
2. **Every caveats row has evidence, or an unverified mark.** Met. `:379` records the audit:
   "Row count: **33**. Rows marked `UNVERIFIED`: **4** (B17, B18, B19, B20)." Each of the four
   states why no code trace exists.
3. **No fork-only path appears.** Met. A case-insensitive search for `fork` in the runbook
   returns 0 hits.

## Verification steps

```bash
# criterion 2 — the row audit the document states about itself
grep -n "Row count" docs/nix-darwin-getting-started.md
grep -c "UNVERIFIED" docs/nix-darwin-getting-started.md

# criterion 3 — no fork-only path
grep -c -i "fork" docs/nix-darwin-getting-started.md    # expect 0

# criterion 1 — the runbook's own exit test
sed -n '274,300p' docs/nix-darwin-getting-started.md
```

An adopter runs the exit test at `:274` on their own machine. This repository cannot run it,
because the machine is already set up.

## Follow-up notes

- **Criterion 1 needs an external reader.** No agent and no owner run can prove "a reader who
  follows only the runbook, on a stock Mac". The runbook is complete and its own exit test is
  written. Treat the external walk-through as feedback, not as unfinished work.
- **Four caveats rows stay `UNVERIFIED`** (B17 to B20). Each row names why: the claim comes from
  a task definition and no code trace remains. Delete a row or promote it when evidence appears.
- **Task 010 asks for one more line here.** Its spike decision wants the adopter lock baseline
  in this runbook: one 4.1 MB fetch, about 55 KB of lock text, no SSH. A grep for `4.1 MB` and
  `lock text` in the runbook returns nothing today.
