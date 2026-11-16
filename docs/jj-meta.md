---
type: Reference
description: The jj-meta CLI that attributes a jj change to the agent session that produced it — trailer profiles, session autodiscovery, the mutable-only rule, JSON output and exit codes.
timestamp: 2026-11-16T09:35:00+01:00
---

# `jj-meta`

`jj-meta` appends the attribution trailers to the description of a jj change. It discovers the
harness, session and model from the environment, adds only the lines that are missing, deduplicates
them, and never deletes or rewrites existing metadata. It is a Go binary under
[`packages/jj-meta/`](../packages/jj-meta/).

## Why

Jujutsu has no arbitrary per-change metadata. `jj metaedit` can change the description, the
author, the committer and the timestamps, but it cannot set a custom key. The operation log is
repo-global and has no public way to attach a session to one change. A commit trailer in the
description is the portable channel: it survives a clone, and `git interpret-trailers` reads it.

The Nixpkgs transparency policy requires an `Assisted-by:` trailer for LLM-assisted commits and
says explicitly that `Co-authored-by:` does not satisfy it. `jj-meta` makes the correct trailer the
easy default instead of a thing a person must remember.

The tool is separate from `kdn-journal` on purpose. `jj-meta` owns jj metadata and needs only `jj`.
`kdn-journal` owns the session and task journal and calls `jj-meta` when it records a change. See
[tasks/2026-11/jj-meta](tasks/2026-11/jj-meta/definition.md) and
[tasks/2026-11/journal-session-identity](tasks/2026-11/journal-session-identity/definition.md).

## Profiles

A profile is one attribution convention. Profiles compose: `--profile` takes a comma-separated list
or repeats, and `JJ_META_PROFILE` sets the default list. The default active set is
`agent,nixpkgs,asf`.

| Profile   | Trailers                         | Use                                                                         |
| --------- | -------------------------------- | --------------------------------------------------------------------------- |
| `agent`   | `Session-Id`, `Harness`, `Model` | The local session key. The journal reads it back.                           |
| `nixpkgs` | `Assisted-by`                    | The Nixpkgs transparency disclosure; also OpenInfra, LocalAI, Flux, Fedora. |
| `asf`     | `Generated-by`                   | The Apache-style disclosure.                                                |
| `github`  | `Co-authored-by`                 | GitHub's avatar and contributor convention. Needs an agent email.           |
| `full`    | all four                         | A repository that accepts every field.                                      |

`--profile` **replaces** the active set. `--coauthor` adds `Co-authored-by` and `--generated` adds
`Generated-by` on top of whatever set is active, so `--coauthor` keeps the default set.

The values are:

```text
Assisted-by: <harness>:<model>
Generated-by: <harness>:<model>
Co-authored-by: <harness> <agent-email>
Session-Id: <session-id>
Harness: <harness>
Model: <model>
```

Rules that hold for every profile:

- `Co-authored-by` names the **agent**. The human is already the author and is never added as a
  co-author.
- `Co-authored-by` needs an agent email: `--coauthor-email` or `JJ_META_COAUTHOR_EMAIL`. The tool
  never uses the local user's address and never invents one.
- `Signed-off-by` is never written. It is the human's DCO certification.
- The default set writes both `Assisted-by` and `Generated-by` because different consumers read
  different lines. The meaning still differs: `Assisted-by` means a human materially revised the
  work, `Generated-by` means mostly machine-authored. Narrow the set with
  `--profile nixpkgs` or `--profile asf` when only one reading is accurate.
- `Session-Id`, `Harness` and `Model` are single-valued: an existing value is kept, and a different
  one is reported as skipped. `Assisted-by`, `Generated-by` and `Co-authored-by` are multi-valued:
  an exact duplicate is skipped, and a distinct value gets its own line.

## Commands

```
jj-meta attribute [<change-id>] [--revset <revset>]
                  [--session <id>] [--harness <name>] [--model <name>]
                  [--profile agent,nixpkgs,asf|github|full]
                  [--trailer key=value] [--coauthor] [--coauthor-email <email>]
                  [--generated] [--no-session] [--allow-immutable] [--dry-run]
jj-meta show [<change-id>]
jj-meta list [--revset <revset>] [--missing]
jj-meta check [--revset <revset>] [--require coauthor]
jj-meta version
jj-meta completion <shell>
```

Global flags: `--json`, `--dir <path>`.

`attribute` defaults to `@`. It refuses a change outside `mutable()` unless `--allow-immutable` is
explicit, and jj itself still refuses to rewrite an immutable change. `--dry-run` prints the plan
and writes nothing. A second run adds nothing and calls no `jj describe`.

`show` prints the body, the parsed trailers and the mutability of one change. `list` prints the
trailer state of every change a revset matches; `--missing` keeps only the changes without
`Assisted-by` or `Generated-by`. `check` exits 1 when a change is missing `Assisted-by`;
`--require coauthor` also requires `Co-authored-by`.

Use `--revset 'main..@'` for a branch gate. `check` does not filter immutable changes: the revset
decides the scope.

## Session autodiscovery

The tool reads the same environment table as `kdn-journal`, in this order:

| Harness    | Session variable                              | Model variable   |
| ---------- | --------------------------------------------- | ---------------- |
| `opencode` | `OPENCODE_SESSION_ID`                         | `OPENCODE_MODEL` |
| `pi`       | `PI_SESSION_ID`                               | `PI_MODEL`       |
| `claude`   | `CLAUDE_CODE_SESSION_ID`, `CLAUDE_SESSION_ID` | `CLAUDE_MODEL`   |
| `codex`    | `CODEX_THREAD_ID`, `CODEX_SESSION_ID`         | `CODEX_MODEL`    |
| `cursor`   | `CURSOR_CONVERSATION_ID`                      | `CURSOR_MODEL`   |
| `gemini`   | `GEMINI_SESSION_ID`                           | `GEMINI_MODEL`   |
| `copilot`  | `COPILOT_SESSION_ID`                          | `COPILOT_MODEL`  |
| generic    | `AGENT_SESSION_ID`                            | `AGENT_MODEL`    |

`AGENT_MODEL` and `JJ_META_MODEL` are the last model fallbacks. A harness with no session ID is
still reported when `AI_AGENT` or `AGENT_HARNESS` names one, so the `Harness` trailer is available.

`--session`, `--harness` and `--model` override the environment. An unknown harness writes no
`Assisted-by` and warns. An unknown model writes `Assisted-by: <harness>` and warns, because the
policy wants a model name and version.

## Preservation and idempotency

The trailer block is the last paragraph when every line of it is `Key: value` or a folded
continuation. A paragraph with prose, a list or a fenced code block is not a trailer block, so the
tool adds a new block after it. The body, the existing trailer text, the trailing blank lines and
the CRLF line endings are preserved. When nothing is missing, the description is written back
byte-identical and `jj describe` is not called.

## JSON output and exit codes

`--json` prints one envelope:

```json
{
  "schema_version": 1,
  "command": "attribute",
  "generated_at": "2026-11-16T09:35:00+01:00",
  "data": {
    "profiles": ["agent", "nixpkgs", "asf"],
    "session": { "harness": "opencode", "session_id": "ses_1", "model": "model" },
    "dry_run": false,
    "changes": [
      {
        "change_id": "sqzunxvvtlzyonoonoqxotyxuxktzrxv",
        "commit_id": "9320c6ec6e0fd99efcb44e96a01298f5ef6eb6e6",
        "mutable": true,
        "added": ["Assisted-by: opencode:model", "Generated-by: opencode:model"],
        "skipped": [],
        "written": true
      }
    ]
  },
  "issues": []
}
```

Exit codes: 0 success, 1 a refused change or a failed `check`, 2 a usage or jj error.

## Tests

- `packages/jj-meta/internal/trailer` covers the parser and the append rules: no description,
  body only, existing block, CRLF, folded values, a fenced block, duplicates, a single-valued key
  with a different value and a trailing blank line.
- `internal/session` covers every environment variable, the priority order and the overrides.
- `internal/attribution` covers every profile, the default set, the co-author email requirement and
  the warnings.
- `internal/jj` runs the real binary against a temporary repository when `jj` is on `PATH`.
- The `jj-meta-attribute` check runs the packaged binary in a sandboxed temporary repository:
  attribute, a second no-op run, the github profile, the gate and the immutable refusal.
