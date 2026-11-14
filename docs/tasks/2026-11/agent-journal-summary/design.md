---
type: Design
description: Go CLI and TUI (`kdn-journal`) that reads repository tasks, session journals, boards and worklogs, with a tolerant parser, compact summary and safe status mutation.
task: definition.md
authored_by: agent
timestamp: 2026-11-15T20:10:00+01:00
---

# Design: `kdn-journal`

## 0. Review record

Two independent adversarial reviews of the first draft found blocking defects in the parser model.
This version folds them in. The findings that changed the design:

- Real task definitions contain unquoted `: ` in `description`, so YAML parsing must degrade to a
  line-based frontmatter reader instead of failing seven tasks.
- The real boards carry state in **date-headed sections** (`## 2026-11-13`) and `item|state` tables,
  not in `## Now`/`## Next`. Date headings are `now`; tables with an item and a state column are
  items; counts cover every section.
- A board with only `## Done` items is not automatically done. Status is inferred from all items.
- Heading matching uses words and an ordered precedence, not substrings. `## Open follow-ups (not
blockers)` must not become `blocked`.
- `LastTouched` reads only the journal files at the top of a session directory. A recursive walk
  hits a container overlay with thousands of files and permission errors.
- A resumed session has several directories with the same id; selectors pick the newest and say
  `1 of N runs`.
- `task status` was unsafe. The command is now `task set-status`, refuses `done` without an existing
  `done.md`, refuses `done` while a `status.md` remains, and writes atomically.
- The one-screen budget is 24 lines, not 40; every line is truncated to the width; `tasks` and
  `sessions` have default limits; the fixture uses the real eight-board session shape.
- JSON uses one envelope and shape tests; internal line numbers and raw YAML values stay out.
- `edit` is cut; `--print-path` covers editor integration. `summary --all` is a compact one-line
  list. `tasks --tree` stays as an opt-in.

## 1. Scope

One binary, `kdn-journal`, under `packages/kdn-journal/`. It reads two trees:

| Tree               | Path                                            | What the tool reads                                                                                    |
| ------------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Repository tasks   | `docs/tasks/<YYYY-MM>/<slug>/`                  | `definition.md`, `design.md`, `status.md`, `done.md`, `.board.md`, `.worklog.md`, sub-task directories |
| Agent session logs | `.cache/agents/<harness>-<YYYYMMDD>-<session>/` | `board.md`, `board-<track>.md`, `worklog.md`, `worklog-<track>.md`, optional `index.md`                |

It never writes a journal. The only writes are `task set-status` (frontmatter) and the TUI's
`$EDITOR` hand-off. It never parses a harness transcript.

The task-level contract is in [definition.md](definition.md) and
[agent-journal.md](../../../.agents/rules/agent-journal.md).

## 2. Command surface

```
kdn-journal summary [--session <dir|id|id@date>] [--task <dir|slug>] [--all]
                    [--track <name>] [--tail N] [--full]
kdn-journal sessions [--harness <name>] [--limit N] [--all] [--json]
kdn-journal tasks [--status <value>|all] [--month YYYY-MM] [--tree]
                  [--limit N] [--all] [--json]
kdn-journal task <dir|slug> [--json] [--print-path]
kdn-journal task set-status <dir|slug> <open|in-progress|done|not-scheduled|blocked>
kdn-journal board <path> [--track <name>] [--raw] [--json] [--print-path]
kdn-journal worklog <path> [--track <name>] [--tail N] [--raw] [--json] [--print-path]
kdn-journal doctor [--parse-only] [--ignore <code>] [--json]
kdn-journal tui
kdn-journal completion <shell>
kdn-journal version
```

Global flags: `--root <path>`, `--json`, `--no-color`, `--width <n>`. `--root` falls back to a
walk up from the current directory until it finds `docs/tasks` or `flake.nix` + (`.jj` or `.git`).
There is no `KDN_ROOT` environment variable.

`summary` chooses the session in this order: `--session`, `$OPENCODE_SESSION_ID` if a matching
directory exists, then the newest session by `LastTouched`. `--session` accepts a full directory, a
relative path, an exact id, an id prefix, or `id@YYYYMMDD`. When several runs share an id, the
newest is used and the header says `1 of N runs`.

`summary` default: one session, main board detail, one line per track board, the last five worklog
headings, and the task pair when `--task` is given. `--track` prints that board in full. `--all` prints one compact line per session (newest first, limit 20).
`--full` removes item and worklog limits. Default limits: 3 items per section, 5 worklog headings,
24 lines for one session.

`tasks` defaults to every task, newest activity first, limited to 20; `--all` removes the limit.
`--status` accepts any value present in the tree plus `all`; an unknown value is a usage error.
`--tree` indents sub-tasks. `task`
accepts an absolute path, a repo-relative path, a slug, or an unambiguous slug prefix. A session
prefix that matches several distinct ids is ambiguous (exit 2); several runs of one id pick the
newest and print `1 of N runs`.
`--print-path` prints the resolved `definition.md` and exits (used by `$EDITOR`).

`board` and `worklog` accept a file, a session directory, or a task directory. A directory
resolves in this order: explicit file name, `board.md`, `.board.md`, then an error that lists the
candidates. `--track` picks `board-<name>.md` or `worklog-<name>.md`. `--print-path` prints the
resolved file. `--raw` prints the file unchanged.

`doctor` is read-only. `--parse-only` checks only that every task definition, board and worklog
parses; it is the gate for the Nix check. `--ignore <code>` suppresses one issue code. The default
exits 1 when any error remains and 0 otherwise; warnings do not fail.

Exit codes: `0` success, `1` findings or errors, `2` usage error or unknown/ambiguous selector.

## 3. Package layout

```
packages/kdn-journal/
├── default.nix
├── go.mod
├── go.sum
├── main.go
├── cmd/
│   ├── root.go          # root command, app context, root discovery
│   ├── summary.go
│   ├── sessions.go
│   ├── tasks.go
│   ├── task.go          # show + set-status
│   ├── board.go
│   ├── worklog.go
│   ├── doctor.go
│   ├── tui.go
│   └── version.go
└── internal/
    ├── frontmatter/     # tolerant YAML frontmatter + safe scalar rewrite
    ├── markdown/        # fence-aware line scanner (headings, bullets, tables)
    ├── board/           # board model, section kinds, items, counts
    ├── worklog/         # dated heading entries
    ├── task/            # task tree discovery, validation, selector
    ├── journal/         # session discovery, selector, task references
    ├── render/          # text and JSON output, truncation
    └── tui/             # bubbletea model, view, update
```

The module path is `kdn-journal` (like `kdn-certs`). Go 1.25.2.

Dependencies: `github.com/spf13/cobra`, `gopkg.in/yaml.v3`, `github.com/charmbracelet/bubbletea`,
`github.com/charmbracelet/lipgloss`, `golang.org/x/term`. No other direct dependencies. The TUI uses
a plain rune buffer for the filter, so it does not need `bubbles`. Tests use string fixtures, not `testdata/` files.

## 4. Core contracts

### 4.1 `internal/frontmatter`

```go
type Document struct {
    Raw             []byte
    Body            []byte
    Values          map[string]any
    HasFrontmatter  bool
    FrontmatterError string // non-empty when YAML was invalid and the fallback reader ran
}

func Parse(data []byte) *Document
func ParseFile(path string) (*Document, error)

func (d *Document) String(key string) string
func (d *Document) Strings(key string) []string // tags only: YAML list or comma-separated scalar
func (d *Document) Time(key string) (time.Time, bool)

func SetScalar(data []byte, key, value string) ([]byte, error)
```

Rules:

- Frontmatter starts at byte 0 with a `---` line and ends at the next `---` or `...` line.
- Missing frontmatter is not an error for a board or worklog. `Parse` returns
  `HasFrontmatter=false`, `Body=Raw`.
- A present but invalid YAML block is not an error. `Parse` sets `FrontmatterError` and fills
  `Values` with a line-based fallback: each top-level `key: value` line is split at the first
  colon; surrounding quotes are removed; an inline ` #` comment is removed when the value is
  unquoted. This is what keeps the seven real `description: …: …` definitions readable.
- `ParseFile` returns an error only for I/O failures.
- Unknown keys stay in `Values`; typed readers ignore them.
- `Time` accepts RFC 3339, `YYYY-MM-DD`, and `YYYY-MM-DD HH:MM:SS ±ZZZZ`. A YAML `time.Time`
  value is also accepted.
- `SetScalar` scans only top-level lines (no leading whitespace), replaces the first matching
  `key:` line, and inserts before the closing delimiter when absent. It preserves CRLF and every
  other byte. It returns an error when the document has no frontmatter.

### 4.2 `internal/markdown`

```go
type Kind int

const (
    KindBlank Kind = iota
    KindHeading
    KindBullet
    KindTable
    KindFence
    KindProse
)

type Line struct {
    Kind     Kind
    Level    int    // heading level
    Text     string // heading text, bullet text, or prose
    Indent   int    // leading spaces
    Marker   string // "-", "*", "+", "1.", "1)"
    Checkbox int    // -1 none, 0 open, 1 done
    Cells    []string // table cells
    Number   int    // 1-based line number
}

func Scan(data []byte) []Line
func Headings(lines []Line) []Line
func Tables(lines []Line) [][]Line
```

`Scan` is the single fence-aware scanner. Fence state is decided once: a line whose first
non-space run is ``` or ~~~ opens a fence; the matching character with at least the same length
closes it. Every line inside a fence is `KindFence`, including lines that look like headings,
bullets or tables.

Headings are ATX only (`#`, `##`, …). A bullet is a line whose first non-space text starts with
`-`, `*`, `+`, or `N.` / `N)`; `Indent` is the number of leading spaces; `Checkbox` is `0`/`1`
for `[ ]`/`[x]` and `-1` otherwise. A table row is a line with at least one `|` that belongs to a
table whose separator row (`---`, `:---`, …) follows it; `Tables` returns each table as its rows
without the separator.

### 4.3 `internal/board`

```go
type Kind string

const (
    KindNow     Kind = "now"
    KindNext    Kind = "next"
    KindBlocked Kind = "blocked"
    KindDone    Kind = "done"
    KindNotes   Kind = "notes"
    KindOther   Kind = "other"
)

type Item struct {
    Text    string
    State   string // raw state cell or state phrase
    Extra   []string
    Done    bool
    Blocked bool
    Dropped bool
    Depth   int
    Section string
    Line    int
}

type Section struct {
    Title  string
    Level  int
    Kind   Kind
    Parent *Section
    Items  []Item
    Prose  []string
}

type Counts struct {
    Open    int
    Done    int
    Blocked int
    Dropped int
}

type Board struct {
    Path           string
    Title          string
    Description    string
    Status         string // active | blocked | done | unknown
    Updated        time.Time
    Tags           []string
    Sections       []Section
    HasFrontmatter bool
    ModTime        time.Time
}

func ParseFile(path string) (*Board, error)
func Parse(data []byte, path string, modTime time.Time) (*Board, error)

func (b *Board) Items(kind Kind) []Item
func (b *Board) Counts() Counts
```

Heading classification, in order. Normalize to lowercase words (strip punctuation and backticks,
collapse spaces):

1. A heading containing `not blocker` / `not blockers` is `next`.
2. `blocked`, `blocker`, `blockers`, `waiting`, `on hold`, `gated` -> `blocked`.
3. `done`, `completed`, `finished`, `shipped`, `resolved` -> `done`.
4. `now`, `current`, `in progress`, `doing`, `active`, `status`, `state`, `run state`,
   `check state`, `open items`, `sub items`, `items`, `deliverables`, `tracks`, `lanes` -> `now`.
5. A heading containing both `notes` and `next` -> `notes`; otherwise `next`, `todo`, `to do`,
   `remaining`, `follow up`, `follow ups`, `followup`, `followups`, `not started`, `queued`,
   `owner actions` -> `next`.
6. `notes`, `where we are`, `context`, `plan`, `review`, `risks`, `caveats`, `evidence`,
   `hypotheses`, `reference`, `order`, `commits`, `verified state`, `why`, `root cause`, `fix`,
   `result`, `contract`, `verification`, `controls`, `blast radius`, `harness`, `host`, `goal`
   -> `notes`.
7. A heading that contains a date (`YYYY-MM-DD`) -> `now`.
8. Anything else -> `other`.

A notes/other section that carries an item+state table with at least one open row is promoted to
`now` after parsing; this is the structural backstop for headings such as
`## Containers review cycle (2026-11-14)`.

A `###` subsection inherits its nearest ancestor's kind when its own heading is `other`. This
keeps `## Items` items and `### f. Cleanups` items in one kind.

Items:

1. A line whose first non-space text is a bullet starts a new item. `Depth = Indent / 2`.
   `[ ]` / `[x]` set `Done`. An ordered marker (`1.`, `1)`) is a bullet.
2. A non-blank line indented deeper than the current item's marker column and not a bullet appends
   to the previous item's text. A blank line does not close the item. A non-blank line at or left
   of the marker column and not a bullet closes it.
3. A table row is an item when the table has an item-like column (header contains `item`, `task`,
   `what`, `name`, `track`, `lane`, `step`, `check`, or `deliverable`) **and** a state-like column
   (header contains `state`, `status`, or `done`). `Text` is the item cell, `State` the state cell,
   `Extra` the remaining cells. Tables without a state column stay prose; `Check|Result` is prose.
4. A bullet's own text may carry a state phrase: an em/en dash or colon followed by
   `**done**`, `**blocked**`, `done`, `blocked`, `committed`, `verified`, `dropped`, and similar.
   This is what makes `- 005 ssh-ca — **blocked**: …` work without a checkbox.

State vocabulary on a whole table cell (trimmed, case-insensitive, trailing `—`, `:`, `,` allowed):

| Class   | Values                                                                                                                                        |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| done    | `done`, `complete`, `completed`, `closed`, `shipped`, `committed`, `verified`, `pass`, `passed`, `✓`, `✔`, `x`                                |
| blocked | `blocked`, `blocker`, `waiting`, `hold`, `on hold`, `gated`                                                                                   |
| dropped | `dropped`, `cancelled`, `abandoned`, `n/a`, `wontfix`, `not applicable`                                                                       |
| open    | everything else, including `in progress`, `queued`, `not started`, `pending`, `todo`, `running`, `documented`, `gap`, `unprovable`, `not run` |

`x` is done only as the whole cell, never as a substring. A state cell that starts with `done`
followed by `—`, `(`, `,` or `:` is done (`DONE — 5 reports`, `done (prettier-formatted)`).

`Counts` covers every section, including `other` and date-headed sections. A nested bullet (depth
greater than zero) is part of its parent and is not counted separately. `Open` excludes done,
blocked and dropped items; `Blocked` and `Dropped` are separate. `Status` is the frontmatter
`status` normalized (`in-progress`/`open` -> `active`), else: any blocked -> `blocked`; any open ->
`active`; any done and no open/blocked/dropped -> `done`; else `unknown`. A board with only a
`## Done` section and no other items is done; a board with a `## Lanes` table is active.

`Updated` is the frontmatter `updated`, then `timestamp`, then the file mtime. `Title` is the
frontmatter `title`, then the first H1 with a leading `Board — `, `Board – `, `Board - ` or
`Board: ` stripped, then the file base name without `.md`; when the H1 is exactly `Board`, the
parent directory name is used. A board with no recognized section still parses; `Counts` may be
non-zero from tables and state-bearing bullets.

### 4.4 `internal/worklog`

```go
type Entry struct {
    Heading      string
    Timestamp    time.Time
    HasTimestamp bool
    Body         string
    Line         int
}

type Worklog struct {
    Path    string
    Entries []Entry
    ModTime time.Time
}

func ParseFile(path string) (*Worklog, error)
func Parse(data []byte, path string, modTime time.Time) (*Worklog, error)
func (w *Worklog) Tail(n int) []Entry
```

An entry starts at a level-2 heading, or at a level-1 heading when the file has no level-2
heading. Fence-aware. The timestamp is the first `YYYY-MM-DD` or RFC 3339 text anywhere in the
heading, so `## Verbatim reports — 2026-10-15` is dated. A heading with no date keeps
`HasTimestamp=false`; the renderer prints `—` instead of a zero time. `Tail(n)` returns the last
`n` entries in file order, even when the file is not chronological.

### 4.5 `internal/task`

```go
type File struct {
    Name    string
    Path    string
    Kind    string // definition | research | design | status | done | board | worklog | other
    ModTime time.Time
}

type Issue struct {
    Severity string // error | warning
    Code     string
    Path     string
    Message  string
}

type Task struct {
    Dir            string
    RelDir         string
    Month          string
    Slug           string
    Depth          int
    ParentDir      string
    DefinitionPath string
    Title          string
    Description    string
    Status         string // free string; known: open | in-progress | done | not-scheduled | blocked | active
    Solution       string
    AuthoredBy     string
    Timestamp      time.Time
    Files          []File
    HasBoard       bool
    HasWorklog     bool
    Board          *board.Board
    Worklog        *worklog.Worklog
    Subtasks       []*Task
    LastActivity   time.Time
    OpenItems      int
    DoneItems      int
    BlockedItems   int
    DroppedItems   int
    Issues         []Issue
}

type Tree struct {
    Root  string
    Tasks []*Task
}

func Load(root string) (*Tree, error)
func (t *Tree) Find(selector string) (*Task, error)
func (t *Tree) Active() []*Task
func (t *Task) Validate() []Issue
```

Discovery walks `root/docs/tasks`. A directory is a task when it holds `definition.md`; every other
directory is only traversed. Hidden directories are skipped. A task's parent is the nearest
ancestor task directory; its month is the first path component under `docs/tasks` (for example
`2026-11`). A sub-task keeps the parent's month.

Files are listed from the task directory (not recursive). `Kind` is derived from the name:
`definition.md`, `research.md`, `design.md`, `status.md`, `done.md`, `.board.md` / `board.md`,
`.worklog.md` / `worklog.md`, `<sub>.research.md` / `<sub>.design.md` -> `research` / `design`,
everything else -> `other`.

`LastActivity` is the task board's `Updated`, then the definition `timestamp`, then the maximum
mtime of the task files as a tiebreak. This survives a jj checkout that resets every mtime.

`Title` is the frontmatter `title`, then the first body H1, then the slug. `Description` is the
frontmatter `description`.

Validation (doctor). Every issue carries a stable code:

| Code                     | Condition                                             | Severity |
| ------------------------ | ----------------------------------------------------- | -------- |
| `frontmatter-invalid`    | present frontmatter failed YAML and used the fallback | warning  |
| `frontmatter-missing`    | no frontmatter                                        | error    |
| `type-not-task`          | `type` is not `Task`                                  | error    |
| `status-missing`         | no `status`                                           | error    |
| `status-unknown`         | status is not a known value                           | warning  |
| `authored-by-missing`    | no `authored_by`                                      | error    |
| `timestamp-missing`      | no `timestamp`                                        | warning  |
| `month-mismatch`         | directory month differs from the timestamp month      | warning  |
| `done-without-solution`  | `status: done` with no `solution`                     | error    |
| `solution-missing`       | `solution` names a file that does not exist           | error    |
| `done-without-done-file` | `status: done` without `done.md`                      | error    |
| `done-with-status-file`  | `status: done` with a `status.md`                     | error    |
| `done-file-while-open`   | `done.md` while the status is not done                | warning  |
| `status-file-while-open` | `status.md` while the status is not `in-progress`     | warning  |
| `duplicate-slug`         | two tasks share a slug                                | warning  |

The month check is the documented rule: the month comes from the `timestamp`, and a task is never
moved to a new month. The check compares the path month with the timestamp month.

`Find` order: exact absolute path, exact repo-relative path, exact `RelDir`, exact slug, unique
slug prefix. An ambiguous match returns every candidate in the error. A slug that collides with a
subcommand is still reachable by path.

### 4.6 `internal/journal`

```go
type Session struct {
    Dir          string
    RelDir       string
    Name         string
    Harness      string
    Date         string // YYYYMMDD from the name
    DateParsed   time.Time
    ID           string
    LastTouched  time.Time
    Boards       []*board.Board // index order, then main, then tracks
    Worklog      *worklog.Worklog
    TrackWorklogs []*worklog.Worklog
    TaskRefs     []string // repo-relative task directories found in the files
    Issues       []task.Issue
}

type Store struct {
    Root     string
    Sessions []*Session // newest first
}

func Load(root string) (*Store, error)
func (s *Store) Newest() *Session
func (s *Store) Matches(selector string) ([]*Session, error)
func (s *Store) Find(selector string) (*Session, []*Session, error)
func (s *Store) ForTask(t *task.Task) []*Session
```

The directory name is parsed as `<harness>-<YYYYMMDD>-<session>`. Harness is `[a-z0-9]+`; the date
is exactly eight digits; the session id is the rest, including dashes and underscores. A name that
does not match is still loaded: `Harness` and `Date` stay empty, `ID` is the whole name, and an
issue is recorded. `DateParsed` uses the local timezone at midnight.

`LastTouched` is the newest mtime of the session directory itself and its top-level
`board*.md`, `worklog*.md` and `index.md` files. It never descends into `poc/` or a container
overlay, and it skips unreadable entries.

`Boards` order: links in an optional `index.md` first (in listed order), then `board.md`, then
`board-*.md` sorted by name. Duplicates are removed. `Worklog` parses `worklog.md`; every
`worklog-*.md` becomes a `TrackWorklogs` entry. `TaskRefs` are extracted from the raw board and
worklog text: strip `#fragment`, `:NN` and `:NN-MM`, strip a trailing `{a,b}.md`, `.md` or `/`,
require exactly `<YYYY-MM>/<slug>`, drop `README` and anything that does not exist under
`docs/tasks`, and keep the longest existing task directory prefix. A session whose id appears in a
task board is also related to that task.

`Find` accepts an exact directory, a relative path, an exact id, an id prefix, or `id@YYYYMMDD`.
When several runs share an id, `Find` returns the newest and the full match list; the text renderer
prints `1 of N runs`. Several runs with the same id and date are all returned; the newest is
selected, and the header still says `1 of N runs`.

## 5. Output

### 5.1 Text

Text is the default. Color is enabled only when stdout is a TTY, `--no-color` is absent, and
`NO_COLOR` is unset. Width defaults to 100 and is set by `--width`.
Every rendered line is truncated to the width with a tail ellipsis; ids use a middle ellipsis.
`--full` removes the item and worklog limits. JSON ignores width and color.

`summary` (one session, no `--all`):

```
SESSION  opencode-20261115-ses_e1f8bbd08ffep6essAsRoa3wna  (2026-11-15, touched 5m ago)
  board.md  Agent journal CLI  [active]
    now      [ ] item  [x] done item  (+2 more)
    next     item; item
    blocked  item — waits for ...
  tracks   3
    board-ssh-ca.md  SSH CA follow-up  [active]  2 open, 1 blocked  next: owner reboot
    board-pi.md      pi harness         [active]  1 open
WORKLOG  12 entries, last 5:
  2026-11-15T19:20:00+01:00  plan review
  ...
TASK     docs/tasks/2026-11/agent-journal-summary  [in-progress]
  board    3 open, 1 done, 1 blocked
  now      ...
  next     ...
  blocked  none
```

The main board gets up to three items per section; each track gets one line. `--track` replaces the
track block with the full detail of that board. The whole block is capped at 24 lines; the renderer
stops adding items and appends `… +N more` when the cap is reached. `--all` prints one line per
session, capped at 20.

`tasks`:

```
TASKS  12 active, 34 done, 1 other
  [in-progress]  2026-11  agent-journal-summary  Go CLI and TUI for tasks and journals
    docs/tasks/2026-11/agent-journal-summary  last 5m ago  2 open, 1 blocked
  [open]         2026-11  ...
```

`--tree` indents a sub-task under its parent with two spaces per depth and omits the month on the
child. `sessions` is one line per session: date, harness, id, last touched, board count, worklog
count, task references. `task` prints the definition, files, board sections, worklog headings and
sub-tasks. `doctor` prints one line per issue with its code and a final count.

### 5.2 JSON

Every read command emits one envelope:

```json
{
  "schema_version": 1,
  "command": "summary",
  "root": "/path/to/repo",
  "generated_at": "2026-11-15T20:00:00+01:00",
  "data": {},
  "issues": []
}
```

`data` is the command payload: `session` and optional `task` for `summary`; `sessions` for
`sessions`; `tasks` for `tasks`; `task` for `task`; `board` for `board`; `worklog` for `worklog`;
`errors` and `warnings` for `doctor` are counts; the issue objects are in the top-level `issues`
array. `summary --all` uses `sessions`. Internal fields (`Line`, raw frontmatter maps) are tagged
`json:"-"`. Optional times are omitted by the model's `MarshalJSON`; a missing worklog timestamp
is omitted, never `0001-01-01`. `issues` is always an array, empty when there is nothing to report. JSON shape
tests cover `summary`, `tasks`, `sessions`, `board`, `worklog` and `doctor`; they assert the
envelope and the command payload rather than a byte-for-byte golden, because `root` and
`generated_at` vary per run.

## 6. TUI

Bubbletea v1 and lipgloss. Two tabs: **Tasks** and **Sessions**.

- Left pane: the filtered list. Tasks show status, month, slug and description. Sessions show
  date, harness, id and board count.
- Right pane: a scrollable preview. `enter` opens the selected item in a full-pane detail view;
  `esc` returns to the list. The detail shows the task definition, board Now/Next/Blocked, worklog
  headings and sub-tasks; for a session it shows the main board, track summary lines and worklog
  headings.
- Header: repository root and the active tab. Footer: `j/k move  enter detail  tab switch  /
filter  e edit  r refresh  q quit`.
- `e` opens the selected primary file in `$EDITOR` (task `definition.md`, session `board.md`) and
  refreshes on exit. It is a no-op with a status-line message when the file is absent.
- `/` enters filter mode. In filter mode every key goes to the text input except `enter` (apply)
  and `esc` (cancel); `q` types a `q`, it does not quit. `tab` and `j/k` are also captured.
- `r` reloads from disk. `q` and `ctrl+c` quit. `g`/`G` jump to the ends; `pgup`/`pgdn` scroll the
  detail.
- The TUI requires a TTY. A non-TTY invocation returns exit code 2 with a clear error.

The model is testable without a terminal. `NewModel(Deps)` takes
`Deps{Tree, Store, Width, Height, Editor, Pager, Reload}`; tests inject fixtures and a fake editor.
No test starts a real program.

## 7. Packaging

`packages/kdn-journal/default.nix` follows `packages/kdn-certs/default.nix`:

- `buildGoModule`, `subPackages = [ "." ]`, source filtered to `go.mod`, `go.sum`, top-level
  directories, `testdata/` (reserved for future fixtures) and `*.go`;
- `installShellFiles` for bash/fish/zsh completions;
- `ldflags = [ "-X main.version=${finalAttrs.version}" ]`, so `kdn-journal version` prints the
  package version;
- `passthru.tests.go-test` as a second `buildGoModule` with `doCheck = true` and an
  `installPhase` that only touches `$out`;
- `meta.mainProgram = "kdn-journal"`.

Wire-up:

- `packages/default.nix`: `kdn-journal = pkgs.callPackage ./kdn-journal { };` inserted above the
  `# AUTO_PACKAGE_PLACEHOLDER #` line.
- `checks/default.nix`: `kdn-journal-test = pkgs.kdn.kdn-journal.passthru.tests.go-test;` and
  `kdn-journal-parse`, a derivation that copies `docs/tasks` into a temporary root and runs
  `kdn-journal doctor --parse-only --root "$root"`.
- `checks/bundles.nix`: add both to `bundle-pkgs`.
- `checks/README.md`: add the two rows, update the attribute count and re-measure `bundle-pkgs`.
- `devenv.nix`: add
  `inputs.nix-configs.packages.${pkgs.stdenv.hostPlatform.system}.kdn-journal` to `config.packages`.

The package is pure Go and has no platform guard. Tests use string fixtures; no `testdata/` is
required in v1, but the source filter keeps the directory so a later fixture does not surprise the
Nix build.

## 8. Tests

Unit tests per package, all using `t.TempDir()` and string fixtures:

- `frontmatter`: delimiters, missing frontmatter, invalid YAML fallback (the real
  `description: …: …` shape), unknown keys, list vs comma tags, time formats, `SetScalar`
  preserves body/comments/CRLF.
- `markdown`: headings, fenced code, bullets, ordered lists, tables, section-less content.
- `board`: structured board, unstructured board, date-headed state table, `item|state|where`
  table, `Track|Scope|State` table, checkbox and state-phrase items, `not blockers` heading,
  inherited subsection kinds, blocked/done inference, missing frontmatter, no headings, nested
  bullets, continuation lines, `Board —` title stripping.
- `worklog`: dated headings, date anywhere in the heading, undated headings, fenced code, tail
  order, non-chronological files.
- `task`: discovery, nesting, month inheritance, month-vs-timestamp warning, selectors, every
  validation code, `LastActivity` from frontmatter, `set-status` preservation and refusals.
- `journal`: name parsing, newest order, selectors with duplicate ids, `id@date`, task
  references (including `:443-448` and `{definition,research}.md`), missing `.cache/agents`,
  unreadable subdirectory, top-level-only `LastTouched`, optional `index.md`.
- `render`: summary contains the session, task and worklog lines; the real eight-board fixture
  stays at or under 24 lines; every line is at or under the width; `--full` expands; JSON shape
  tests cover the envelope and the command payload.
- `tui`: tab switch, cursor movement, filter mode captures `q`, detail open/close, edit no-op,
  non-TTY error.

One integration test walks up from the package directory to the repository root. When it finds
`docs/tasks`, it parses every definition, every task `.board.md`/`.worklog.md`, every session
`board*.md` and `worklog*.md`; when it does not (the Nix sandbox), it skips. The Nix
`kdn-journal-parse` check copies `docs/tasks` into the sandbox and runs `doctor --parse-only`, so a
broken task file fails a check even without `.cache/agents`.

## 9. Acceptance commands

```bash
cd packages/kdn-journal
go test ./...
go vet ./...
gofumpt -l .          # no output
cd ../..

SYS=x86_64-linux      # or aarch64-darwin on anji
nix build .#kdn-journal
nix build ".#checks.$SYS.kdn-journal-test"
nix build ".#checks.$SYS.kdn-journal-parse"

./result/bin/kdn-journal summary
./result/bin/kdn-journal summary --task docs/tasks/2026-11/agent-journal-summary
./result/bin/kdn-journal tasks
./result/bin/kdn-journal task agent-journal-summary
./result/bin/kdn-journal doctor --parse-only
./result/bin/kdn-journal doctor
./result/bin/kdn-journal tui
```

The summary for the real eight-board session must stay at or under 24 lines and every line must fit
the width. `doctor` may report pre-existing issues; the acceptance is that it runs, classifies them
with stable codes, and that `doctor --parse-only` exits 0. The `tui` check is manual: it opens, the
tabs switch, and `q` quits.

## 10. Delegation and review loops

The owner asked for orchestration through less capable models, with adversarial loops on the plan
and on the result.

- **Plan loop:** two independent reviewers read this design plus the task definition, the rule and
  real boards. One focuses on parser and data-model edge cases; the other on command UX, TUI,
  packaging and acceptance. Findings are folded into this document and the task board before code.
  This round produced the changes in §0.
- **Implementation split:** parsers (`frontmatter`, `markdown`, `board`, `worklog`), discovery
  (`task`, `journal`), rendering and CLI, TUI, and docs are separate work packets with disjoint
  file ownership. The orchestrator owns `go.mod`, `main.go`, `cmd/root.go`, `default.nix`, the
  integration, and every fix.
- **Result loop:** two independent reviewers read the final code and run the acceptance commands.
  One is a code reviewer (bugs, edge cases, error handling, races); the other is an acceptance
  verifier (real-repo parse, line count, JSON, TUI compile, Nix build). Findings are fixed and the
  loop repeats until no blocking finding remains.

## 11. Risks and mitigations

| Risk                                                 | Mitigation                                                                                                                                                                             |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Free-form boards vary too much                       | `markdown.Scan` decides fences once; heading kinds are ordered words; tables need both an item and a state column; a board with no recognized section still parses and reports counts. |
| Invalid YAML in real definitions                     | `frontmatter.Parse` falls back to a line reader and reports a warning code; `doctor --parse-only` still passes.                                                                        |
| Weak implementation agents produce inconsistent APIs | This document fixes the signatures; the orchestrator writes the skeleton and reviews every packet.                                                                                     |
| TUI dependencies inflate the Nix build               | Only bubbletea and lipgloss; `vendorHash` is computed once and pinned.                                                                                                                 |
| A task file is edited by another session             | `task set-status` rewrites only the `status:`/`solution:` lines, refuses `done` without `done.md`, refuses `done` while a `status.md` remains, and writes via a temp file + rename.    |
| The summary grows past one screen                    | 24-line budget, 3 items, 5 headings, track lines, `--full` opt-in; the real eight-board fixture asserts the bound and the width.                                                       |
| Nix sandbox lacks the repository                     | Unit tests use temp fixtures; `kdn-journal-parse` copies `docs/tasks` into the sandbox; the `.cache/agents` walk is local-only and skips when absent.                                  |
