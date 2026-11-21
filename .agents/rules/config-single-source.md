---
type: Rule
description: A profile knob has one home — hosts-den/brys/strata-profiles.nix — and every consumer derives from the generated config.json; a guard test proves the agreement.
timestamp: 2026-11-21T21:00:00+01:00
---

# One knob, one file

A **profile knob** is a number that says how one operating point of the Strata engine serves: its
context window, its slot count, its VRAM reserve and its resident K/V. Every knob has exactly one
home: `hosts-den/brys/strata-profiles.nix`.

## The rule

1. **One knob, one file.** The `profiles` table in `hosts-den/brys/strata-profiles.nix` is the only
   place a profile's `maxContext`, `parallel`, `reserveMiB` and `kvResident` are written. Add a
   profile by adding a row there — not by adding a default anywhere else.
2. **Every consumer derives.** The deployment file is generated from that table
   (`/etc/kdn-inference-helpers/config.json`), and a consumer reads it:
   - the manager reads it through `config.ProfileSpec` and serves it;
   - `strata-serve.sh` reads it with `jq` and **fails loudly** when a key is missing — no literal
     fallback, no default;
   - `status --long` renders the same values.
     A consumer may derive a value that is a function of a knob (the yarn factor is the window over
     the model's native window), but it may not hold a second copy of the knob.
3. **A guard test proves the agreement.** `checks/inference-helpers/profiles.nix` imports the
   deployment file, reads the generated `config.json`, and runs `strata-serve.sh <profile> --print`
   to get the argv it would really build. It asserts that the window, the slot count, the reserve
   and the resident K/V agree for every profile in `textProfiles`, that every such profile has a
   policy row with measured facts, and that every alias resolves to something servable. It also
   fails on the two shapes the drift took before: a context literal in `strata-serve.sh` and a
   built-in profile table in `strata.go`.
   A failure names the profile and both values.

Run the guard alone:

```bash
nix build --no-eval-cache -L '.#checks.x86_64-linux.inference-helpers-profiles'
```

It is a member of `bundle-pkgs`.

## Why

The rule exists because the drift was real, not hypothetical. On 2026-11-21 the slot count lived in
**three** places at once:

- `hosts-den/brys/strata-profiles.nix` → the generated `config.json` (`max-multi = 5`),
- `hosts-den/brys/strata-serve.sh` → a hardcoded `parallel=6` in its own `case` table,
- `packages/kdn-inference-helpers/internal/engine/strata/strata.go` → a built-in table with
  `Parallel: 6`.

Two consequences followed. The manual fallback served six slots while the manager served five, and
the manager served the two omni profiles with **8** slots while the Nix file said 1 and 2 — the
measured colo shape was not the shape the manager ran. A second copy of a number is not a
convenience; it is a future disagreement with no owner.

## Adding a profile

1. Add one row to `profiles` in `hosts-den/brys/strata-profiles.nix` (the helper derives the yarn
   factor; `conversationCacheMiB = null` means "keep the base config's value").
2. Add it to `textProfiles` (if it serves chat) and add its alias and `frontierIDs` entry.
3. Add its measured facts to `hosts-den/brys/policy.nix` with `profile = "<name>"`, so
   `status --long` shows numbers; the guard fails when a frontier profile has no such row.
4. Run the guard, then deploy, then restart `strata-manager` (it caches `config.json`) and
   `ctl down && ctl up`.

`hosts-den/brys/policy.nix` holds **measured facts** (VRAM footprint, K/V reserve, load and switch
seconds), not knobs; it is a second file by design, and the guard checks that the two agree on the
profile set.
