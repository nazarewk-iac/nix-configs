---
type: Reference
description: The kdn-jj-meta CLI that attributes a jj change to the agent session that produced it — trailer profiles, session autodiscovery, the mutable-only rule, JSON output and exit codes.
timestamp: 2026-11-16T09:35:00+01:00
---

# `kdn-jj-meta`

`kdn-jj-meta` appends the attribution trailers to the description of a jj change. It discovers the
harness, session and model from the environment, adds only the lines that are missing, deduplicates
them, and never deletes or rewrites existing metadata. It is a Go binary under
[`packages/kdn-jj-meta/`](../packages/kdn-jj-meta/).

## Why

Jujutsu has no arbitrary per-change metadata. `jj metaedit` can change the description, the
author, the committer and the timestamps, but it cannot set a custom key. The operation log is
repo-global and has no public way to attach a session to one change. A commit trailer in the
description is the portable channel: it survives a clone, and `git interpret-trailers` reads it.

The Nixpkgs transparency policy requires an `Assisted-by:` trailer for LLM-assisted commits and
says explicitly that `Co-authored-by:` does not satisfy it. `kdn-jj-meta` makes the correct trailer the
easy default instead of a thing a person must remember.

The tool is separate from `kdn-journal` on purpose. `kdn-jj-meta` owns jj metadata and needs only `jj`.
`kdn-journal` owns the session and task journal and calls `kdn-jj-meta` when it records a change. See
[tasks/2026-11/kdn-jj-meta](tasks/2026-11/kdn-jj-meta/definition.md) and
[tasks/2026-11/journal-session-identity](tasks/2026-11/journal-session-identity/definition.md).

## Profiles

A profile is one attribution convention. Profiles compose: `--profile` takes a comma-separated list
or repeats, and `KDN_JJ_META_PROFILE` sets the default list. The default active set is
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
- `Co-authored-by` needs an agent email: `--coauthor-email` or `KDN_JJ_META_COAUTHOR_EMAIL`. The tool
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
kdn-jj-meta attribute [<change-id>] [--revset <revset>]
                       [--session <id>] [--harness <name>] [--model <name>]
                       [--profile agent,nixpkgs,asf|github|full]
                       [--trailer key=value] [--coauthor] [--coauthor-email <email>]
                       [--generated] [--no-session] [--allow-immutable] [--allow-empty]
                       [--dry-run]
kdn-jj-meta show [<change-id>]
kdn-jj-meta list [--revset <revset>] [--missing]
kdn-jj-meta check [--revset <revset>] [--require coauthor]
kdn-jj-meta skill [--dir <path>]
kdn-jj-meta version
kdn-jj-meta completion <shell>
```

Global flags: `--json`, `--jsonl`, `--dir <path>`.

`attribute` defaults to `@`. It refuses a change outside `mutable()` unless `--allow-immutable` is
explicit, and jj itself still refuses to rewrite an immutable change. `--dry-run` prints the plan
and writes nothing. A second run adds nothing and calls no `jj describe`. A change with an empty
description is skipped unless `--allow-empty` is given: an empty `@` is not a commit yet.

`show` prints the body, the parsed trailers and the mutability of one change. `list` prints the
trailer state of every change a revset matches; `--missing` keeps only the changes without
`Assisted-by` or `Generated-by`. `check` exits 1 when a change is missing `Assisted-by`;
`--require coauthor` also requires `Co-authored-by`.

`--jsonl` prints one JSON object per line with no envelope: one change for `attribute`, `show`,
`list` and `check`, and one object for `skill` and `version`. It is the form to pipe into `jq`. A change with an empty description is skipped,
so a gate over `mutable()` or `main..@` passes while `@` is still empty.

Use `--revset 'main..@'` for a branch gate. `check` does not filter immutable changes: the revset
decides the scope.

### `skill`

`kdn-jj-meta skill` prints the cross-repo skill the binary embeds. `--dir <path>` writes it to
`<path>/kdn-jj-meta/SKILL.md`, the layout an agent harness reads. Home Manager installs the same
file into `~/.agents/skills`, `~/.config/opencode/skills` and `~/.pi/agent/skills`, so an agent in
any repository can load it without a checkout of this one. `--json` returns `{id, markdown}`.

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

`AGENT_MODEL` and `KDN_JJ_META_MODEL` are the last model fallbacks. A harness with no session ID is
still reported when `AI_AGENT` or `AGENT_HARNESS` names one, so the `Harness` trailer is available.

`--session`, `--harness` and `--model` override the environment. An unknown harness writes no
`Assisted-by` and warns. An unknown model writes `Assisted-by: <harness>` and warns, because the
policy wants a model name and version.

## Local models

The fleet serves the same name from different profiles over a day: `qfn` is `max` (whole card,
UD-IQ4_XS) in the morning and `omni-fast` (IQ2_XS plus a reserve) in the afternoon, and an image
editor is its own profile. A trailer that says only `qfn` therefore records which alias was typed,
not what ran.

`--local-model` records the pair, one trailer per model:

```sh
kdn-jj-meta attribute @ --local-model qfn=max
kdn-jj-meta attribute @ --local-model 'qwen-image-edit=image-qwen (Qwen-Image-Edit-2511 Q4_K_M)'
```

```
Local-model: qfn=max
Local-model: qwen-image-edit=image-qwen (Qwen-Image-Edit-2511 Q4_K_M)
```

- A bare alias (`--local-model qfn`) is resolved against the manager: the tool asks
  `/status` on `KDN_INFERENCE_MANAGER_URL` (default `http://127.0.0.1:8181`) which profile is
  current and appends it. The manager is the only component that knows, because it is the thing
  that swaps.
- `alias=profile` is kept verbatim. The profile the caller names wins over the one the manager
  reports: the caller may know that the work happened before the swap.
- An unreachable manager leaves the bare alias. A commit never fails because the serving host is
  asleep.
- `KDN_JJ_META_LOCAL_MODELS` (comma separated) supplies the default list, so a harness that knows
  which models it used does not have to repeat flags.
- Record only models that actually contributed to the change. A model that served an unrelated
  request is not part of the change; a configuration change *about* a model is not the model
  doing the work.

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

- `packages/kdn-jj-meta/internal/trailer` covers the parser and the append rules: no description,
  body only, existing block, CRLF, folded values, a fenced block, duplicates, a single-valued key
  with a different value and a trailing blank line.
- `internal/session` covers every environment variable, the priority order and the overrides.
- `internal/attribution` covers every profile, the default set, the co-author email requirement and
  the warnings.
- `internal/jj` runs the real binary against a temporary repository when `jj` is on `PATH`.
- `cmd` covers the four profiles, the idempotent second run, the immutable refusal and the JSON
  envelope.
- The `kdn-jj-meta-attribute` check runs the packaged binary in a sandboxed temporary repository:
  attribute, a second no-op run, the github profile, the agent profile, the gate and the immutable
  refusal.
