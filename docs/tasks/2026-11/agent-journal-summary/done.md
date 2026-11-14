---
type: Solution
description: A Go CLI and TUI (`kdn-journal`) that reads repository tasks and agent journals, prints a one-screen summary, validates both trees and browses them interactively.
task: definition.md
authored_by: agent
timestamp: 2026-11-15T21:10:00+01:00
---

# Solution: `kdn-journal`

## Root cause analysis

The repository already had a task convention and a journal contract, but no single reader. The
state lived in free-form Markdown at four levels: the session board, one board per parallel track,
the task board and the task worklog. Catching up meant opening several files and rebuilding the
state by hand. The original task proposed `hack/board-summary.py`; the owner chose a Go CLI plus a
TUI under `packages/`, so the tool could be one compiled artifact, share the repository's existing
cobra and bubbletea stack, and expose the same models as JSON.

The real inputs also disagreed with the first design in ways only a review found: seven task
definitions carry an unquoted `: ` in `description` (invalid YAML), the useful state sits in
date-headed `item | state` tables rather than `## Now`, one session directory holds a 4,499-entry
container overlay, and resumed sessions can share an id across two directories. The parser and the
discovery code are shaped around those facts, not around the ideal board.

## Solution

### Package

`packages/kdn-journal/` is a self-contained Go module (Go 1.25.2) with:

| Package                | Responsibility                                                                                                                                                                                                           |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `internal/frontmatter` | Tolerant YAML frontmatter; a line fallback for invalid YAML; `SetScalar` preserves every other byte.                                                                                                                     |
| `internal/markdown`    | One fence-aware line scanner: headings, bullets, ordered items, tables, prose.                                                                                                                                           |
| `internal/board`       | Heading classification, date-headed tables, state phrases, inherited subsection kinds, counts, status inference.                                                                                                         |
| `internal/worklog`     | Dated entries; a date anywhere in the heading; `Tail`.                                                                                                                                                                   |
| `internal/task`        | Task tree discovery, parent/depth/month, selectors, stable validation codes.                                                                                                                                             |
| `internal/journal`     | Session discovery, top-level-only `LastTouched`, duplicate-id selection, `index.md` order, task references.                                                                                                              |
| `internal/render`      | Text output with width truncation, a 24-line summary cap and ANSI-aware colour.                                                                                                                                          |
| `internal/tui`         | Bubbletea browser: `bubbles/list` for the list/filter/pagination, `bubbles/viewport` for detail scrolling, `bubbles/help` and `key` for the footer, `glamour` for Markdown; Tasks and Sessions tabs, `$EDITOR` hand-off. |
| `cmd`                  | Cobra commands, JSON envelope, exit codes, safe `task set-status`.                                                                                                                                                       |

Commands: `summary`, `sessions`, `tasks`, `task`, `task set-status`, `board`, `worklog`, `doctor`,
`tui`, `completion`, `version`. Every read command accepts `--json`; `--root`, `--width`,
`--no-color` are global.

### Behaviour that matters

- A board without frontmatter, without a known heading, or with a table under a date heading still
  parses. Counts cover date-headed sections and tables; a plain bullet in a notes section is prose.
- `## Open follow-ups (not blockers)` is `next`, not `blocked`. A date heading is `now` after the
  vocabulary rules, and a notes/other section with an open `item | state` table is promoted to
  `now`.
- `LastTouched` reads only the top-level board and worklog files, so a container overlay cannot
  select an old session. A session prefix that matches distinct ids is ambiguous; several runs of
  one id pick the newest and print `1 of N runs`.
- `task set-status done` refuses a task without `done.md`, refuses a task that still has
  `status.md`, writes `solution: done.md`, and writes through a temp file and a rename.
- The summary is 21 lines for the eight-board session that motivated the task, and every line fits
  the requested width.

### Packaging and docs

- `packages/kdn-journal/default.nix`: `buildGoModule`, shell completions, version ldflags, and a
  `passthru.tests.go-test` derivation.
- `packages/default.nix`, `checks/default.nix`, `checks/bundles.nix`: the package and two checks
  (`kdn-journal-test`, `kdn-journal-parse`).
- `devenv.nix`: the CLI is on the shell PATH.
- `.agents/rules/agent-journal.md`: the recommended board shape and the catch-up commands.
- `docs/tasks/README.md`: how to read the state with `kdn-journal`.
- `docs/kdn-journal.md`: the full command, board, JSON, exit-code and editor reference.
- `AGENTS.md`: the docs-table row.

## Verification steps

```text
$ cd packages/kdn-journal && go test ./...
?       kdn-journal      [no test files]
ok      kdn-journal/cmd
ok      kdn-journal/internal/board
ok      kdn-journal/internal/frontmatter
ok      kdn-journal/internal/journal
ok      kdn-journal/internal/markdown
ok      kdn-journal/internal/render
ok      kdn-journal/internal/task
ok      kdn-journal/internal/tui
ok      kdn-journal/internal/worklog

$ go vet ./...            # no output
$ gofumpt -l .            # no output
$ go test -race ./...     # all packages ok
```

```text
$ nix build .#kdn-journal
$ nix build .#checks.x86_64-linux.kdn-journal-test
$ nix build .#checks.x86_64-linux.kdn-journal-parse
# all succeed; the parse check prints "DOCTOR 0 errors, 0 warnings / clean"

$ devenv shell -- kdn-journal version
kdn-journal 0.1.0
```

```text
$ kdn-journal --width 100 summary \
    --session opencode-20261110-ses_e3c837bf2ffeKUFIukMf5s2OB2 \
    --task agent-journal-summary | wc -l
21
# max line width: 100 runes

$ kdn-journal doctor --parse-only
DOCTOR  0 errors, 0 warnings
  clean

$ kdn-journal doctor
DOCTOR  9 errors, 10 warnings
# exit 1; the nine errors are pre-existing done-without-solution tasks

$ kdn-journal tui </dev/null
kdn-journal: kdn-journal tui requires a terminal: stdout is not a TTY
# exit 2
```

The real-repository tests parse 139 task definitions, 22 boards and 28 worklogs. They
assert the eight-board summary stays at or under 24 lines and every line stays at or under the
width. `kdn-journal-parse` repeats the task-tree parse in the Nix sandbox.

## Follow-up notes

- `doctor` reports nine pre-existing `done-without-solution` errors in old tasks and ten warnings
  (seven `frontmatter-invalid` line fallbacks, two `status-file-while-open`, one other). They are
  outside this task; `doctor --parse-only` is the clean gate.
- The TUI uses `bubbles/list` for the list, filtering, pagination and status bar;
  `bubbles/viewport` for the detail scroll; `bubbles/help` and `bubbles/key` for the footer; and
  `glamour` for the Markdown detail. The quit keys and filter capture are covered by the model
  tests. The TUI was opened under tmux at 120x40: it rendered, `/` filtered the task list, and `q`
  returned to the shell. Its `$EDITOR` hand-off accepts an editor with arguments (`code -w`,
  `nvim -u NONE`).
- Text colour uses `golang.org/x/term` for TTY detection, so `/dev/null` is not mistaken for a
  terminal. `--no-color` and `NO_COLOR` both disable it.
- The JSON shape is covered by shape tests, not byte-for-byte goldens: `root` and `generated_at`
  vary per run. Optional times are omitted instead of emitted as `0001-01-01`.
- Bubble Tea v1 calls `lipgloss.HasDarkBackground()` in its package init, before `main`. The
  packaged binary's wrapper sets `CI=1` so `termenv` skips the OSC 11 query; `main` restores `CI`
  before the CLI runs, and the TUI sets an explicit dark background. Without the wrapper,
  `kdn-journal version` can leave a late terminal response in the shell.
- Agent-facing use is documented in [`.agents/rules/kdn-journal.md`](../../../../.agents/rules/kdn-journal.md)
  and [docs/kdn-journal.md#for-agents](../../../kdn-journal.md#for-agents): JSON reads,
  explicit `--session`/`--root`, `doctor --parse-only` as the gate, and `task set-status` as the
  only write.
- A future `kdn-journal` version can add a `doctor --baseline` file for the pre-existing findings,
  and a `summary --watch` mode. Neither is needed for the current contract.
