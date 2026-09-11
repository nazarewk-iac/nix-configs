---
type: Solution
description: Measured answers to the flake input overhead questions — the adopter cost is near the floor, one root-level follows line is the only real defect, and the subflake spike waits.
task: definition.md
authored_by: agent
timestamp: 2026-09-11T12:00:00Z
---

# 010 — flake input overhead, answered

Parent: [definition.md](definition.md). The measurements: [research.md](research.md).

## Root cause analysis

A 106-node `flake.lock` looks expensive, so the assumption was that an adopter pays for all of
it. The assumption was wrong, and no measurement existed to correct it.

Lix's lock format is lazy at both ends. At lock time `computeLocks` copies an unchanged input as
metadata, with no I/O. At evaluation time `call-flake.nix` wraps every `fetchTree` in a
`mapAttrs`, so Lix never fetches a node nothing references. An adopter pays for the tree they
asked for, and for the lock text. Nothing else.

Two earlier leads were grep-level facts, and the task told the next pass to test both before it
concluded anything (`definition.md:118-131`). One held and one failed:

- Lix 2.95.2 holds zero `lazy-trees` references. Confirmed.
- `lix/libfetchers/path.cc:129` is **not** the error a `?dir=` subflake hits when it reads
  `../../lib`. That line sits in `PathInputScheme::fetch`, and only a `path:` input reaches it.

So the real defect is small: **one root-level `follows` line** makes every adopter lock run
refetch the whole tree.

## Solution

[research.md](research.md) is the deliverable the task names at `definition.md:133-145`. It
answers all three required parts.

| Part | Line | Content |
|---|---|---|
| Q1 — the adopter lock and re-lock cost | `:55` | **confirmed** |
| Q2 | `:231` | **confirmed** |
| Q3 — the subflake shape | `:301` | **confirmed** |
| Q4 | `:380` | **confirmed** |
| the ranked technique lists, (a) this repository and (b) an adopter | `:403-461` | ranked by value against effort |
| the plain statement | `:462` | "Very little helps, and here is why" |
| the spike decision | `:473-475` | **"Do not spike the subflake yet."** |
| corrections to the task file | `:484` | four rows |
| the reproduction | `:493` | every command, each run outside this repository |

The headline numbers: a fresh adopter pays one 4.1 MB tree fetch and 54 841 bytes of lock text.
The first lock run takes 1.2 s. A read of `lib.kdn` plus the package overlay takes 0.14 s. Lix
fetches zero of the other 100 lock nodes.

The verdict at `:14` is **"Very little helps."** The task asked for exactly that answer if the
measurements gave it, so the task is complete with no code change.

## Verification steps

```bash
D=docs/tasks/2026-09/generalization/010-flake-input-overhead/research.md

# each question carries a confirmed tag
grep -n "confirmed" "$D" | sed -n '1,12p'

# the plain statement and the spike decision
grep -n "^## The plain answer" "$D"
grep -n "^## Spike decision" "$D"

# the reproduction commands, to re-measure on demand
sed -n '493,560p' "$D"
```

Every command in the reproduction section runs **outside** this repository, in a scratch
directory. Nothing in this task builds a host, so no check bundle gates it.

## Follow-up notes

Two recommended actions from the spike decision stay **un-applied**. Both belong to the owner.

1. **The one-line fix is still open.** A root-level `follows` line makes every adopter lock run
   fetch the whole tree. `research.md:471` calls it a four-line fix. The research cites
   `flake.nix:7`; that reference has drifted, because `flake.nix:7-13` now holds the adopter
   note. The root-level line sits at **`flake.nix:18`** today. Apply it under the Pattern V1
   gate, then re-count the adopter `got tree` lines.
2. **The runbook records no adopter baseline.** Step 2 asks 003's runbook to state one 4.1 MB
   fetch, about 55 KB of lock text, and no SSH. A grep for `4.1 MB` and `lock text` in
   `docs/nix-darwin-getting-started.md` returns nothing.

Revisit the subflake on one of two triggers only: an adopter reports the lock text as a real
problem, or checkpoint 002 finds an adopter-visible fault that a 3-input subflake fixes.
