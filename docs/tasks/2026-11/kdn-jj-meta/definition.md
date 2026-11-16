---
type: Task
description: A separate kdn-jj-metadata tool that attributes mutable changes to an agent session by adding missing commit trailers, never deleting existing metadata, with Assisted-by as the default disclosure.
status: open
authored_by: agent
timestamp: 2026-11-16T09:10:00+01:00
---

# `kdn-jj-meta`: attribute jj changes to agent sessions

## Context

`kdn-journal` now has a local-first session model: a session directory, a `session.json` sidecar,
and optional Atuin Threads. The missing link is the jj side: a change has no arbitrary metadata
field, and the journal should not be the tool that edits commit descriptions.

This is a separate concern and a separate tool:

- **`kdn-jj-meta`** owns jj commit metadata (trailers). It is generic; it does not read `.cache/agents`.
- **`kdn-journal`** owns the session/task journal and calls `kdn-jj-meta` when it needs to attribute a
  change. The sidecar is local-first; Atuin is an optional transcript fallback.

The Nixpkgs transparency policy requires an `Assisted-by:` trailer for LLM-assisted commits and
explicitly says `Co-authored-by:` does not satisfy it. The tool should make the correct trailer the
easy default, not make the user remember it.

## Goal

One command attributes a selected jj change to the current agent session:

```sh
kdn-jj-meta attribute <change-id>
```

It discovers the harness/session from the environment, appends the missing trailers to the change
description, deduplicates them, and never deletes or rewrites existing metadata. It works only on
mutable changes by default.

## Scope

### 1. Trailer policy and profiles

The tool covers several attribution conventions without forcing every project to accept every
trailer. A **profile** is one convention; the profiles compose into a set, and the default set is
`agent,nixpkgs,asf`. `--trailer key=value` adds one more line.

| Profile   | Trailers                         | Use                                                                                                |
| --------- | -------------------------------- | -------------------------------------------------------------------------------------------------- |
| `agent`   | `Session-Id`, `Harness`, `Model` | The local session key; `kdn-journal` reads it back.                                                |
| `nixpkgs` | `Assisted-by`                    | Nixpkgs, OpenInfra, LocalAI, Flux, Fedora; any consumer that reads a dedicated disclosure trailer. |
| `asf`     | `Generated-by`                   | Apache-style projects that use `Generated-by`.                                                     |
| `github`  | `Co-authored-by`                 | GitHub’s avatar/contributor convention. Requires an agent email.                                   |
| `full`    | all four                         | Maximum coverage for a repo that accepts all of them.                                              |

Default values:

```text
Assisted-by: <harness>:<model>
Generated-by: <harness>:<model>
Session-Id: <session-id>
Harness: <harness>
Model: <model>
```

- `Assisted-by:` is the disclosure required by Nixpkgs. The value names the tool and the primary
  model/version. Example: `Assisted-by: opencode:deepseek-v4.1-flash-1017`.
- `Session-Id:` is the local attribution key. It is included when a session is known; `--no-session`
  suppresses it.
- `Harness:` and `Model:` are redundant with `Assisted-by` for humans, but make the metadata
  machine-readable without parsing the combined value.
- `Co-authored-by:` is **not** in the default set. `--profile github` or `--coauthor` adds
  `Co-authored-by: <agent> <email>` for the agent, never for the human author. An email is required;
  the tool never invents one or uses the local user.
- `Generated-by:` is part of the default set through the `asf` profile. Narrow the set with
  `--profile nixpkgs` when the work is materially human-revised, or `--profile asf` when it is
  mostly machine-authored.
- A change with an empty description is skipped unless `--allow-empty` is given. An empty `@` is
  not a commit, and attributing it is the mistake the agent rule warns about.
- `check` skips an empty description too, so a gate over `mutable()` passes while `@` is empty.
- `Signed-off-by:` is never written by this tool. It is the human’s DCO certification.
- Existing lines are preserved. The tool appends only missing `Key: value` lines.
- Multi-valued keys (`Assisted-by`, `Co-authored-by`, `Generated-by`) deduplicate exact values and
  allow multiple distinct values. Single-valued keys (`Session-Id`, `Harness`, `Model`) are left
  alone when any value exists.
- The default active set is `agent,nixpkgs,asf`; a repository can set `KDN_JJ_META_PROFILE` to another
  comma-separated set. `--profile` replaces the set; explicit `--trailer` lines always win.

### 2. Mutable-only by default

- The default target is `@`.
- `--revset <revset>` targets several changes.
- Every target is intersected with `mutable()`. An immutable target is an error unless
  `--allow-immutable` is explicit.
- The tool never creates, abandons, rebases or pushes a change. It only rewrites the description of
  an existing mutable change.

### 3. Session autodiscovery

- `--session`, `--harness` and `--model` override the environment.
- Otherwise detect the harness and session ID from the same environment table as `kdn-journal`:
  `OPENCODE_SESSION_ID`, `PI_SESSION_ID`, `CLAUDE_CODE_SESSION_ID`, `CODEX_THREAD_ID`,
  `CURSOR_CONVERSATION_ID`, `GEMINI_SESSION_ID`, `COPILOT_SESSION_ID`, `AGENT_SESSION_ID`.
- Model detection: `--model`, then a harness-specific variable (`PI_MODEL`, `OPENCODE_MODEL`,
  `CLAUDE_MODEL`, `CODEX_MODEL`, `AGENT_MODEL`), then `unknown`.
- If the harness is unknown, the tool still works with `--harness`/`--model`; it does not guess.
- If the model is unknown and `--allow-unknown-model` is absent, the command warns and writes
  `Assisted-by: <harness>` rather than inventing a model.

### 4. Commands

```
kdn-jj-meta attribute [<change-id>|--revset <revset>] [--session <id>] [--harness <name>]
                  [--model <name>] [--profile agent,nixpkgs,asf|github|full]
                  [--trailer key=value] [--coauthor] [--coauthor-email <email>]
                  [--generated] [--no-session] [--allow-immutable] [--allow-empty]
                  [--dry-run] [--json]
kdn-jj-meta show <change-id> [--json]
kdn-jj-meta list [--revset <revset>] [--missing] [--json]
kdn-jj-meta check [--revset <revset>] [--require coauthor] [--json]
kdn-jj-meta version
```

- `attribute`: print the change ID, the added trailers and the skipped existing trailers; `--json`.
- `show`: print the description, parsed trailers and mutability.
- `list`: list changes with their trailer state; `--missing` only those missing `Assisted-by`.
- `check`: exit 1 when a mutable change is missing `Assisted-by`; `--require coauthor` also requires
  the optional `Co-authored-by` (for projects that mandate it).
- `--dry-run`: print the plan and change nothing.

### 5. Integration

- `kdn-journal` writes `session.json` with the local session, jj change IDs/commits and optional
  Atuin UUID. It calls `kdn-jj-meta attribute <change-id> --session <id> --harness <harness> --model
<model>` when a change is recorded, or leaves the call to the agent.
- `kdn-journal` never parses or edits jj metadata itself; it reads the trailers through
  `kdn-jj-meta show --json` when it needs to display attribution.
- The sidecar remains the local source of truth. Atuin is an optional transcript fallback, not a
  requirement for attribution.
- `kdn-jj-meta` is independent of `kdn-journal` and Atuin; it only needs `jj`.

### 6. Agent VCS rule

Add a rule to the agent VCS guidance:

> Before an agent commits, run `kdn-jj-meta attribute <change-id>` (or let the commit helper call it).
> Every agent-assisted commit carries `Assisted-by:` with the harness and model. Do not add
> `Co-authored-by:` for the human author; the human is already the author. Do not add
> `Signed-off-by:` on behalf of the agent.

The commit helper can call `kdn-jj-meta` and then `jj commit`/`jj describe` with explicit paths.

## Acceptance

- `kdn-jj-meta attribute` on a mutable change appends the selected profile's missing trailers
  (`Assisted-by`, `Session-Id`, `Harness`, `Model` by default), is idempotent, deduplicates exact
  trailers, and preserves the body and every existing trailer.
- `--profile github` adds the agent `Co-authored-by` only when an agent email is supplied; the human
  author is never added.
- `--profile asf`/`--generated` adds `Generated-by`; `--profile full` adds every supported field.
- An immutable change is refused unless `--allow-immutable`.
- `kdn-jj-meta check` exits 1 for a missing `Assisted-by` and 0 when present; `--json` is stable.
- `kdn-jj-meta show` and `list` parse existing trailers without rewriting them.
- A fixture covers: no description, description without trailers, existing `Assisted-by` with a
  different value, duplicate lines, `Co-authored-by` from another agent, CRLF, and an immutable
  change.
- `kdn-journal` can attribute a recorded change through the CLI without importing the tool as a
  library.
- `go test ./...`, `nix build .#kdn-jj-meta`, and the package check pass.

## Out of scope

- Creating, splitting, squashing or pushing commits.
- Removing or rewriting existing trailers.
- Reading `.cache/agents` or Atuin.
- Replacing `jj describe`/`jj metaedit`; the tool only augments descriptions.
- Enforcing policy on already-pushed/immutable history.

## Open questions

1. Should `Session-Id:` be default-on (useful attribution, public) or opt-in (private)?
2. Should `Assisted-by` use `harness:model` or `harness (model)`? Pick one and keep it parseable.
3. Should `Co-authored-by` be a per-project config rather than a global flag?
4. Should the tool also write `Generated-by` for fully generated changes?
5. Does the agent commit helper belong in `kdn-jj-meta` or `kdn-journal`?
