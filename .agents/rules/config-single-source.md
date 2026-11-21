---
type: Rule
description: A frontier serving knob has exactly one home — the model itself in data/llm.nix (hosts.<host>.serving) — and every consumer is a Nix expression over it; there is no second copy, so there is no guard check.
timestamp: 2026-11-21T22:40:00+01:00
---

# One knob, one file — and nothing to validate

A **frontier serving knob** is a number that says how one operating point of the Strata engine
serves: its base pack, its context window, its slot count, its VRAM reserve, its resident K/V, its
park pool, its n-gram backing store, and the measured facts the placement policy quotes.

## The rule

1. **One home: the model.** Every knob is written on the model that serves it, in
   `data/llm.nix`, under `hosts.<host>.serving`. Add an operating point by adding one model entry
   with its `serving` block — never by adding a default, a table or a fallback anywhere else. The
   entry's key is the llama-swap name; its `serving.profile` is the operating point that name
   forces; `serving.rank` orders `textProfiles` (rank 0 rests); `serving.colo = true` marks a point
   that keeps a reserve for a companion.
2. **Every consumer is a derivation.** `lib/llm.nix` `strata data "<host>"` is the only reader, and
   it yields, from that one block:
   - the manager's `config.json` — `profiles`, `textProfiles`, `aliases`, `frontierIDs`
     (`hosts-den/brys/strata-profiles.nix`);
   - the llama-swap `cmd` of the entry — `strata-select <profile> --alias <entry> --port ${PORT}`
     (`modules/den/aspects/llm.nix`, `strataProfile`);
   - the placement policy's frontier rows — `vramMiB`, `kvReserveMiB`, `ramMiB`, `loadSeconds`,
     `switchSeconds` — and `coloProfiles` (`hosts-den/brys/policy.nix`);
   - the engine argv, because `strata-serve.sh` reads the generated `config.json` with `jq` and
     **fails loudly** when a key is missing — no literal fallback, no default;
   - the yarn factor (`ropeScale` = served window / `servers.<host>.frontier.nativeContext`), so no
     entry writes a rope value of its own.
3. **There is no guard check, because there is no second copy.** A validation test exists to catch
   two copies drifting apart. Here the numbers have one home and every consumer is an expression
   over it, so `checks/inference-helpers/profiles.nix` was deleted on 2026-11-21: it asserted that
   a file agreed with itself. If a consumer ever needs a value that is a _function_ of a knob, write
   the function — not a copy.

Behaviour that must stay identical is proven by the artifacts, not by a check: `config.json` and
`policy.json` diff clean against the previous deployment, `strata-serve <profile> --print` prints
the same argv, and `status --long` shows the same facts.

## Why

The rule exists because the drift was real, not hypothetical. On 2026-11-21 the slot count lived in
**three** places at once:

- the deployment file → the generated `config.json` (`max-multi = 5`),
- `hosts-den/brys/strata-serve.sh` → a hardcoded `parallel=6` in its own `case` table,
- `packages/kdn-inference-helpers/internal/engine/strata/strata.go` → a built-in table with
  `Parallel: 6`.

Two consequences followed. The manual fallback served six slots while the manager served five, and
the manager served the two omni profiles with **8** slots while the file said 1 and 2 — the
measured colo shape was not the shape the manager ran. A second copy of a number is not a
convenience; it is a future disagreement with no owner.

The 2026-11-21 follow-up moved the remaining copies into `data/llm.nix`: the `config.json` tables,
the `strata-select <profile>` strings in each entry, and the policy's frontier facts. That is what
made the guard check unnecessary rather than merely satisfied.

## Adding an operating point

1. Add one model entry to `data/llm.nix` under the frontier section: its identity (`capabilities`,
   `gpu`, `contextSize`), its `hosts.brys.serving` block (profile name, `rank`, pack, window, slots,
   reserve, resident K/V, park pool, `pleIO`, measured facts), and its `hosts.brys.common` (file,
   download off). For a second name for a point that exists, add a llama-swap alias to the existing
   entry instead of a new entry — one point, one `serving` block.
2. Deploy. `config.json` gains the profile, `textProfiles` gains it at its `rank`, `aliases` and
   `frontierIDs` gain its names, the llama-swap entry is generated, `status --long` shows its facts
   and the policy sees its row.
3. Restart `strata-manager` (it caches `config.json`) and `ctl down && ctl up`.

`hosts-den/brys/policy.nix` keeps the behaviour tree, the card budget, the companions, the small
models and the image profiles. It holds no frontier knob and no frontier measured fact: those are
on the model, next to the window and the reserve that produced them.
