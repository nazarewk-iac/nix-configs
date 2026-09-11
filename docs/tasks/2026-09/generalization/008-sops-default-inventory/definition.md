---
type: Task
description: Produce an exact list of what depends on the default sops file, its key schema, and which consumers fail when the file is absent.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 008 — default sops file inventory

Hub: [../generalization-plan.md](../definition.md). Independent of the direction gate.
Run it any time after 001. Checkpoint 009 needs its output.

Goal: a crystallized list. The creator asked for depth here, so the deliverable is an inventory,
not a refactor. Do **not** change any module in this checkpoint.

## Why this blocks 009

Checkpoint 009 moves all personal data into one folder. The tree must still evaluate when the
folder is absent. The default sops file is the hardest case, because two mechanisms compete:

1. A **discovery** mechanism that reads the sops YAML metadata and derives the secret set from it.
   When the file is absent, the derived set is empty, not absent.
2. **Consumers that index a literal key path** into that derived set. An empty set makes the index
   fail at evaluation time, not at build time.

Mechanism 2 defeats mechanism 1. So "set `allow = false` and the tree evaluates" is a claim, not a
fact, until this inventory proves it per consumer.

## One verified failure already found

`modules/universal/networking/tailscale/default.nix:11` reads a literal key path:

```nix
  authKeys = config.kdn.security.secrets.sops.secrets.default.tailscale.default.auth_keys;
```

Line 17 then feeds it to `builtins.attrNames` inside an option **type**:

```nix
      type = lib.types.enum ([ null ] ++ builtins.attrNames authKeys);
```

With the default sops file absent, evaluation fails with `error: attribute 'default' missing` at
that line. Nix evaluates an option `type` whether or not the module is enabled, so
`lib.mkIf cfg.enable` does not protect it. This is the shape of unguarded consumer to hunt for.

## The four lists to produce

### List 1 — the key schema

Every key path the tree reads out of the default sops file, with the file and line that reads it.
Group by top-level key. State the value shape each consumer expects (string, attrset of names,
list).

This list is the schema an adopter must satisfy to reuse the affected modules. Nothing writes it
down today.

### List 2 — the consumers

Every file that reaches into the default sops secrets. For each row record:

| Column | Meaning |
|---|---|
| File and line | where |
| Key path | what it reads |
| Guard | `.allowed`, `util.hasSops`, `lib.mkIf`, or **none** |
| Guard position | inside `config`, or inside an option `type`/`default` |
| Absent-file behaviour | evaluates, or fails — **verified, not assumed** |

The guard position column matters more than the guard column. A guard inside `config` does not
protect an option `type` or a `default` in the same file.

### List 3 — the unguarded consumers

Extract the rows from list 2 whose absent-file behaviour is "fails". This is the work list for 009.
Rank it by how hard the fix is: a `default = { }` fallback, a `or` fallback, a lazier option type,
or a real restructure.

### List 4 — the hard couplings

The sites that hardwire the file path or the key layout. They do not read a discovered value. Start
from `modules/universal/profile/default-secrets/default.nix`. It pins `sopsFile` to a path under
the flake root at three sites, plus that file's key layout. **The count is confirmed: four sites in
two files** — three in `modules/universal/profile/default-secrets/default.nix` and one in
`modules/universal/profile/remote-builders/default.nix`. See `research.md`.

## Method

- Verify each absent-file claim by evaluation, not by a read of the source. The tailscale finding
  above came from an evaluation trace, and it contradicts what the guard pattern suggests.
- Reach the absent-file state, but delete nothing from the working copy. Evaluate a host from a
  scratch flake that overrides the sops file path to an absent path. Or set the allow switch off.
  Use whichever reproduces the failure above.
- Do not report a consumer as guarded because it uses `lib.mkIf cfg.enable`. Check option `type`
  and `default` expressions separately.
- An evaluation error names one failure at a time. Expect to iterate: fix nothing, but stub each
  failure locally to reach the next one, and discard the stubs.

## Deliverable

A `.research.md` sibling, in the shape of
[jj-experiments-subset-check.research.md](../../jj-experiments-subset-check/research.md), with the four
lists above. Each row carries a file and line reference. Tag every absent-file behaviour cell
**verified** or **unverified**.

## Exit criteria

- All four lists exist, and every row in list 2 has a file and line reference.
- Every absent-file behaviour cell carries a verified or unverified tag, with no blanks.
- List 3 ranks the rows by fix effort.
- 009 can start from list 3 with no further discovery.

## Out of scope

Do not fix any consumer — that is 009. Do not move the sops file — that is 009. Do not change the
discovery engine. Do not re-key or re-encrypt anything.
