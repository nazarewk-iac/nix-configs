---
type: Solution
description: A four-list inventory of the default sops file — its key schema, its 22 consumers with a verified absent-file behaviour each, an effort rank, and the four hard couplings.
task: definition.md
authored_by: agent
timestamp: 2026-09-11T12:00:00Z
---

# 008 — the default sops file inventory, landed

Parent: [definition.md](definition.md). The lists: [research.md](research.md).

## Root cause analysis

Many modules read one default sops file, and no list of them existed. So nobody could say what
breaks when the file is absent, and 009 had no place to start.

The guard pattern hid the real coupling. A reader sees `lib.mkIf cfg.enable` and concludes the
consumer is safe. That conclusion is wrong when an option `default` expression reads the file
path, because a `default` evaluates outside the `mkIf`. The task states the rule directly at
`definition.md:95-96`: check option `type` and `default` separately.

A source read could not settle the question either. The task requires an evaluation per claim
(`definition.md:90-91`), because one earlier finding contradicted what the source suggested. An
evaluation error also names one failure at a time, so the audit had to iterate with throwaway
stubs (`definition.md:97-98`).

## Solution

[research.md](research.md) holds the four lists the deliverable names. It is 25 069 bytes.

| List | Line | Content |
|---|---|---|
| 1 — the key schema | `:116` | every key the default sops file must hold |
| 2 — the consumers | `:145` | 22 rows. Each row carries a `file:line` and a bold **verified** tag for its absent-file behaviour |
| 3 — the effort rank | `:189` | the same rows, ordered by fix effort, so 009 starts at the top |
| 4 — the hard couplings | `:203` | the sites that cannot take an absent file |
| the transcript | `:257` | the evaluation runs behind the verified tags |
| notes for 009 | `:351` | what 009 inherits |

The four hard couplings sit in two files:

- `modules/universal/profile/default-secrets/default.nix:22,31,35,97`
- `modules/universal/profile/remote-builders/default.nix:206`

Each exit criterion:

1. **All four lists exist, and every list 2 row has a `file:line`.** Met.
2. **Every absent-file cell carries a verified or unverified tag, with no blank.** Met. All 22
   rows carry a bold **verified** tag.
3. **List 3 ranks the rows by fix effort.** Met, at `:189`.
4. **009 starts from list 3 with no further discovery.** Met. List 4 names the exact lines, and
   `:351` states what 009 inherits.

The task changed no module, which its own out-of-scope section demands
(`definition.md:114-117`).

## Verification steps

```bash
D=docs/tasks/2026-09/generalization/008-sops-default-inventory/research.md

# the four lists exist
grep -n "^## " "$D"

# every consumer row carries a verified tag and no blank cell
grep -c "\*\*verified\*\*" "$D"

# the four hard couplings still sit where list 4 says
grep -n "sops" modules/universal/profile/default-secrets/default.nix | sed -n '1,10p'
grep -n "sops" modules/universal/profile/remote-builders/default.nix | sed -n '1,10p'
```

The research file records the evaluation transcript at `:257`. Do not re-run it to confirm the
inventory; run it again only when a consumer changes.

## Follow-up notes

- **009 owns every fix.** This task deliberately changed nothing. Read list 3 top-down.
- **The two hard-coupling files gate 009's first batch.** A consumer that reads the path in an
  option `default` needs a different fix from one that reads it under a `mkIf`.
- **Keep the verified tags fresh.** A row's absent-file behaviour is a measurement, not a
  property of the source. When a consumer changes, re-run its part of the transcript at `:257`.
