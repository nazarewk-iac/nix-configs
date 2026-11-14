---
type: Design
description: Go CLI that appends missing Assisted-by/Session-Id trailers to mutable jj changes, autodetects the harness session, deduplicates, and never deletes metadata.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T09:10:00+01:00
---

# Design: `jj-meta`

## 1. Decisions

| Question            | Decision                                                                   | Reason                                                                     |
| ------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Default disclosure  | `Assisted-by: <harness>:<model>`                                           | Nixpkgs requires it; `Co-authored-by` does not satisfy the policy.         |
| Default profile     | `portable`: `Assisted-by`, `Session-Id`, `Harness`, `Model`                | Covers the dedicated-trailer projects without noisy or misleading fields.  |
| Other profiles      | `github` adds `Co-authored-by`; `asf` adds `Generated-by`; `full` adds all | A project opts into the convention it accepts.                             |
| Session attribution | `Session-Id: <id>` by default when known; `--no-session`                   | The tool exists to attribute changes to sessions; suppression is explicit. |
| Co-author           | Off by default; `--coauthor`/`--profile github` requires an agent email    | Do not put the human author in `Co-authored-by`; do not invent an email.   |
| Mutable only        | Default target `@`, intersected with `mutable()`                           | Rewriting immutable history is unsafe and outside the tool.                |
| Existing metadata   | Never delete or rewrite; append only missing lines                         | Another agent or a human may own the existing text.                        |
| Deduplication       | Exact `key: value` lines; multi-valued keys allow distinct values          | Idempotent without collapsing independent tools.                           |
| Integration         | `kdn-journal` calls the CLI; no library coupling                           | The tools stay separate and testable.                                      |

## 2. Package layout

```
packages/jj-meta/
├── default.nix
├── go.mod
├── go.sum
├── main.go
├── cmd/
│   ├── root.go
│   ├── attribute.go
│   ├── show.go
│   ├── list.go
│   └── check.go
└── internal/
    ├── jj/          # runner: mutable(), description read/write
    ├── trailer/     # parse, append, dedupe, preserve
    ├── session/     # harness/session/model detection
    └── render/      # text/JSON
```

Module path `jj-meta`. Go 1.25.2. Dependencies: `spf13/cobra`, `gopkg.in/yaml.v3` only if config is
needed; otherwise standard library.

## 3. Trailer model

```go
type Trailer struct {
    Key   string
    Value string
}

type Document struct {
    Body     []string
    Trailers []Trailer
    Raw      string
}

func Parse(description string) Document
func (d Document) Render(extra []Trailer) string
```

Parsing rules:

- A trailer block is the trailing run of lines matching `^[A-Za-z0-9-]+: .+$` after the body,
  optionally preceded by one blank line.
- Preserve the exact body, blank lines and existing trailer text. Do not reorder.
- A line that looks like a trailer inside a code fence or a quoted block is not a trailer; use a
  fence-aware scan.
- CRLF is preserved.

Append rules:

- `Assisted-by` and `Co-authored-by` are multi-valued: append a value only when the exact
  `key: value` pair is absent.
- `Session-Id`, `Harness`, `Model`, `Generated-by` are single-valued: leave the existing value
  alone; never overwrite.
- If the description ends with a trailer block, append missing lines to that block. Otherwise add a
  blank line and a new trailer block.
- Never add a blank line inside an existing trailer block; preserve the final newline.

## 4. jj runner

```go
type Runner interface {
    Mutable(ctx context.Context, revset string) ([]Change, error)
    Show(ctx context.Context, rev string) (Change, error)
    Describe(ctx context.Context, rev, description string) error
}

type Change struct {
    ChangeID   string
    CommitID   string
    Description string
    Immutable  bool
}
```

Real runner commands:

```sh
jj log --no-pager -r '<revset>' -T 'change_id ++ "\n" ++ commit_id ++ "\n" ++ description ++ "\0"'
jj log --no-pager -r '<revset> & ~mutable()' -T 'change_id ++ "\n"'
jj describe --no-pager -r '<rev>' -m '<description>'
```

- The default revset is `@`.
- The tool refuses an immutable change unless `--allow-immutable` is set.
- `jj describe` rewrites the committer metadata; the tool reports that.
- No `jj new`, `split`, `squash`, `rebase`, `abandon` or push.

## 5. Session detection

```go
type Session struct {
    Harness string
    ID      string
    Model   string
    Source  string
}
```

Priority:

1. `--session` / `--harness` / `--model`.
2. `OPENCODE_SESSION_ID` -> `opencode`; model `OPENCODE_MODEL` or `AGENT_MODEL`.
3. `PI_SESSION_ID` -> `pi`; model `PI_MODEL`.
4. `CLAUDE_CODE_SESSION_ID` -> `claude`; model `CLAUDE_MODEL`.
5. `CODEX_THREAD_ID` -> `codex`; model `CODEX_MODEL`.
6. `CURSOR_CONVERSATION_ID` -> `cursor`; model `CURSOR_MODEL`.
7. `GEMINI_SESSION_ID` -> `gemini`; model `GEMINI_MODEL`.
8. `COPILOT_SESSION_ID` -> `copilot`; model `COPILOT_MODEL`.
9. `AGENT_SESSION_ID` -> `agent`; model `AGENT_MODEL`.

If the model is unknown:

- with `--allow-unknown-model`, write `Assisted-by: <harness>`;
- otherwise print a warning and write `Assisted-by: <harness>` anyway, because a missing trailer is
  worse than a model-less one. The warning tells the agent to pass `--model`.

## 6. Commands

### `attribute`

```
jj-meta attribute [<change-id>|--revset <revset>]
  [--session <id>] [--harness <name>] [--model <name>]
  [--profile portable|github|asf|full]
  [--trailer key=value] [--coauthor] [--coauthor-email <email>]
  [--generated] [--no-session] [--allow-immutable] [--dry-run] [--json]
```

- Builds the desired trailers from the profile:
  - `portable`: `Assisted-by: <harness>:<model>`, `Session-Id: <id>`, `Harness: <harness>`,
    `Model: <model>`
  - `github`: `portable` + `Co-authored-by: <harness> <email>`
  - `asf`: `Generated-by: <harness>:<model>`, `Session-Id`, `Harness`, `Model`
  - `full`: `Assisted-by`, `Generated-by`, `Co-authored-by`, `Session-Id`, `Harness`, `Model`
  - each `--trailer` adds one custom line
- `--generated` is a shortcut for the `asf` disclosure on the current profile.
- Reads the change description, appends only missing lines, calls `jj describe`.
- Prints added/skipped trailers and the change IDs; `--json` emits `{change_id, added, skipped}`.
- Idempotent: a second run adds nothing.

`--coauthor`, `--profile github` and `--profile full` require `--coauthor-email` or
`JJ_META_COAUTHOR_EMAIL`. The tool never uses the human’s email and never defaults to the local
user. If the email is missing, it refuses and prints the flag. The human is already the author and
is never added as a co-author.

### `show`

```
jj-meta show <change-id> [--json]
```

Prints change ID, commit ID, mutable/immutable, description and parsed trailers.

### `list`

```
jj-meta list [--revset <revset>] [--missing] [--json]
```

Lists changes with trailer state. `--missing` filters to changes without `Assisted-by`.

### `check`

```
jj-meta check [--revset <revset>] [--require coauthor] [--json]
```

- Default revset `mutable() & @` or `main..@`? Use `mutable() & @` for a single change and let the
  caller pass `--revset 'main..@'` for a branch.
- Missing `Assisted-by` is an error (exit 1).
- `--require coauthor` also requires `Co-authored-by`; default is warning only.
- `--json` emits `{errors, warnings, changes}`.

## 7. JSON envelope

```json
{
  "schema_version": 1,
  "command": "attribute",
  "generated_at": "2026-11-16T09:10:00+01:00",
  "data": {
    "changes": [{ "change_id": "...", "added": ["Assisted-by: opencode:model"], "skipped": [] }]
  },
  "issues": []
}
```

No absolute paths, no unstable commit IDs in the contract except where requested.

## 8. Integration with `kdn-journal`

- `kdn-journal` keeps the local `session.json` sidecar and optional Atuin link.
- When it records a change/commit, it can call:

  ```sh
  jj-meta attribute <change-id> --session <id> --harness <harness> --model <model>
  ```

- `kdn-journal` never edits commit descriptions itself.
- `kdn-journal session changes` can call `jj-meta show --json` to display the trailers.
- If `jj-meta` is absent, `kdn-journal` reports a warning and keeps the sidecar mapping.
- Atuin remains optional: attribution works from the sidecar and `jj-meta` alone.

## 9. Agent VCS rule

Add to `.agents/rules/jujutsu-vcs.md` and the commit helper:

- Before an agent commits, run `jj-meta attribute <change-id>` or let the helper call it.
- Every agent-assisted commit carries `Assisted-by:`.
- `Co-authored-by:` is never the human author; it is optional agent attribution only.
- `Signed-off-by:` stays human-only.
- `jj-meta check --revset 'main..@'` is the pre-push/CI gate; `jj` has no commit-msg hook.

## 10. Tests

- Trailer parser: body only, existing trailer block, CRLF, fenced code that looks like a trailer,
  duplicate lines, multiple `Assisted-by`, single-valued `Session-Id`.
- Append: idempotent, preserves body, appends to an existing block, adds a blank line when needed.
- jj runner fake: mutable/immutable, description read/write, missing change, jj unavailable.
- Session detection: every env var, precedence, model fallback, explicit flags.
- `--coauthor` refuses without an email; uses the agent identity; never the human.
- Profiles: `portable` default, `github` adds `Co-authored-by`, `asf` adds `Generated-by`, `full`
  adds all; `--generated` adds only `Generated-by`; `--trailer` overrides/augments.
- `check`: missing `Assisted-by` error, `--require coauthor` warning/error, JSON shape.
- Integration: a real temporary jj repo with a mutable change; attribute twice; assert unchanged
  second time and body preserved.
- Nix: `jj-meta-test`, `jj-meta-parse` with a fixture repo.

## 11. Packaging

- `packages/jj-meta/default.nix`: `buildGoModule`, shell completions, `passthru.tests.go-test`.
- `packages/default.nix`, `checks/default.nix`, `checks/bundles.nix`: package and check.
- `devenv.nix`: binary on the shell PATH.
- Docs: `docs/jj-meta.md`; short `.agents/rules/jj-meta.md` linked from `AGENTS.md`.

## 12. Open questions

1. Default `Session-Id` on or off? The task assumes on; a public repo may prefer opt-in.
2. `Assisted-by` format: `harness:model` vs `harness (model)`; choose one and document it.
3. `Co-authored-by` email: a registered bot identity per project, or a local placeholder?
4. `check` default revset: `@` for a single change or `main..@` for a branch?
5. Should `jj-meta` also own the commit helper, or should `kdn-journal` own it?
