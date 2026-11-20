---
name: kdn-jj-meta
description: Attribute jj changes to the agent session that produced them — append Assisted-by, Generated-by, Session-Id, Harness and Model trailers, deduplicate them, never rewrite existing metadata, and gate a branch with check.
---

# Attribute jj changes with `kdn-jj-meta`

Use this skill when you commit with jj in any repository and an agent assisted the work.

## Before you finish a commit

```sh
kdn-jj-meta attribute <change-id>
```

The tool detects the harness, session and model from the environment and appends the missing
trailers. The default profiles are `agent`, `nixpkgs` and `asf`, so a change carries:

```text
Assisted-by: <harness>:<model>
Generated-by: <harness>:<model>
Session-Id: <session-id>
Harness: <harness>
Model: <model>
```

Rules:

- `Assisted-by` is the Nixpkgs transparency disclosure. `Co-authored-by` does not satisfy it.
- Never add `Co-authored-by` for the human author. The human is already the author. If a project
  wants the GitHub convention, the co-author is the agent:
  `--profile github --coauthor-email <email>`.
- Never add `Signed-off-by` for an agent. That is the human's DCO certification.
- Attribute only a mutable change. The tool refuses immutable history.
- Never attribute the unnamed empty `@` at the tip. Attribute the described change you created.
- `Local-model: <alias>=<profile>` records which locally served model produced the change, with
  the profile that served it (`--local-model qfn=max`). A bare alias is resolved against the
  manager's current profile, because the same alias is `max` before a swap and `omni-fast` after
  it. Repeat per model; record only models that actually contributed.
- Never delete or rewrite an existing trailer. The tool appends only missing lines.

## Narrow the profiles

`--profile` replaces the default set; it takes a comma list or repeats.

| Profile   | Writes                                  |
| --------- | --------------------------------------- |
| `agent`   | `Session-Id`, `Harness`, `Model`        |
| `nixpkgs` | `Assisted-by`                           |
| `asf`     | `Generated-by`                          |
| `github`  | `Co-authored-by` (needs an agent email) |
| `full`    | all four                                |

Use `--profile nixpkgs` when a human materially revised the work, or `--profile asf` when it is
mostly machine-authored.

## Check and inspect

```sh
kdn-jj-meta check --revset 'main..@'     # exit 1 when Assisted-by is missing
kdn-jj-meta show <change-id>             # body, trailers, mutability
kdn-jj-meta list --revset 'main..@' --missing
kdn-jj-meta attribute <change-id> --dry-run
```

`check` requires only `Assisted-by`. `--require coauthor` also requires `Co-authored-by`. jj has no
commit-msg hook, so the gate is a command: run it before you push.

## kdn-journal integration

When `kdn-journal` is installed, one command records the session mapping and attributes the change:

```sh
kdn-journal session record-change <change-id>
```

It stores the mapping in `.cache/agents/<session>/session.json` and calls `kdn-jj-meta`. A missing
`kdn-jj-meta` is a warning; the mapping is still recorded.
