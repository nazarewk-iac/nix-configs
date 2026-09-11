---
type: Task
description: Replace whole-repository store copies with single-file references, so an unrelated edit stops triggering a rebuild.
status: open
authored_by: agent
timestamp: 2026-09-10T00:00:00+02:00
---

# 011 — whole-tree store copies cause unnecessary rebuilds

Hub: [../definition.md](../definition.md).

## The defect

A module that writes `"${inputs.nix-configs}/<path>"` puts the **whole repository tree** into the
store, then reads one file out of it. The derivation then depends on every file in the repository.
So an edit to any unrelated file changes the input hash and forces a rebuild.

A relative path literal — `./../../.agents/rules/x.md` — copies **that one file** instead. The
bytes the consumer receives are identical, and the derivation depends on one file.

The same defect applies to `"${kdnConfig.self}/<path>"`, which resolves through the same tree.

This is the cause to check first when a small edit triggers a large rebuild.

## How this list grows

**Do not sweep the repository for this.** The creator's instruction on 2026-09-10: watch for an
instance while you read code for another reason, and append it here when you find one. A dedicated
inventory run is not wanted, because the fix is cheap per site and the reading happens anyway.

## Instances found so far

Each row was found while porting a slot to a den aspect. `den`-tree ports use a relative path
literal already — the creator chose that route on 2026-09-10. See
[004-den-spike](../004-den-spike/definition.md).

| Site | Reads | Found while |
|---|---|---|
| `modules/slots/nix/default.nix:118,120,121` | 2 skills plus `okf-format.md` | reading order 3 of the den port |
| `modules/slots/zellij/default.nix:110` | the `zellij` skill | reading order 5 of the den port |
| `modules/slots/jj/default.nix:171,176,178` | the `jj-expert` agent prompt, 1 rule, 1 skill | reading order 7 of the den port |
| `modules/slots/jj/fork/default.nix:166,269,271` | 1 doc, 1 rule, 1 skill | reading order 7 of the den port |
| `modules/slots/mcp/basic-memory/default.nix:126` | 1 rule | reading order 6 of the den port |
| `modules/universal/profile/default-secrets/default.nix:21,25,85` | `default.unattended.sops.yaml` | overlaps [008](../008-sops-default-inventory/definition.md) |
| `modules/universal/profile/remote-builders/default.nix:195` | the same sops file | overlaps 008 |
| `modules/universal/profile/machine/baseline/default.nix:69` | the **whole** flake tree — `xdg.configFile."kdn/source-flake".source = kdnConfig.self` | added 2026-09-11; the table missed it |
| `modules/universal/profile/machine/baseline/default.nix:141` | the **whole** flake tree — `environment.etc."kdn/source-flake".source` | added 2026-09-11; the table missed it |

## Notes per site

- `modules/slots/jj/default.nix:171` uses `builtins.readFile`. That reads the file at evaluation
  time, so the tree copy is an evaluation cost and not a build input. It still forces the whole-tree
  fetch. A relative path literal removes both.
- `modules/slots/jj/fork/default.nix:166` builds a shell variable inside a script, so the store
  path lands in the script text. A relative path literal changes only the interpolation.
- The two sops sites under `modules/universal/` carry a second problem: the file holds personal
  data. Fix them with [009](../009-personal-data-folder/definition.md), not on their own.
- `modules/universal/profile/machine/baseline/default.nix:69,141` are different in kind. They copy
  the **whole** tree, not one file, so a relative path literal cannot fix them. The consumer needs
  an option that names what to publish, or the copy goes away.

## Exit criteria

- No `"${inputs.nix-configs}/…"` or `"${kdnConfig.self}/…"` interpolation remains that reads a
  fixed file which a relative path literal can reach.
- One measured before-and-after case: edit an unrelated file, and show the dependent derivation
  keeps its `drvPath`.
- `.agents/rules/nix-conventions.md` states the rule, next to the existing self-reference note.
