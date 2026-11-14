---
type: Design
description: Architecture for a general-purpose OKF v0.2 indexer and TUI, with a JSON cache, goldmark link graph, trust/freshness facets, and the charmbracelet component split proven by kdn-journal.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T08:00:00+01:00
---

# Design: `okf` browser

## 1. Decisions taken

| Question           | Decision                                                                                         | Reason                                                                                                         |
| ------------------ | ------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| Name               | `okf`, package `packages/okf`; `kdn-okf` is an alias if the repo insists on the prefix           | The tool is format-specific, not KDN-specific. A short binary composes better with `fzf`/`jq`.                 |
| Index              | JSON cache + in-memory search for v1; search behind an interface                                 | 1,000 concepts fit easily; SQLite FTS5/Bleve can replace the backend without changing the CLI.                 |
| Markdown structure | `goldmark` AST for headings, links and code fences; the tolerant frontmatter reader for metadata | `goldmark` is already in the dependency graph through `glamour`; it handles nested links and fences correctly. |
| Parser reuse       | Start standalone with the proven parser shape; extract a shared module only if duplication hurts | `kdn-journal` must keep working; a refactor is a separate task.                                                |
| TUI                | `bubbles/list`, `bubbles/viewport`, `bubbles/help`, `bubbles/key`, `glamour`, `lipgloss`         | Proven in `kdn-journal`; no custom list/filter/scroll.                                                         |
| Graph              | JSON and DOT export; backlinks/links views in the TUI                                            | A terminal graph canvas is a separate, low-value problem.                                                      |
| Bundle writes      | None in v1                                                                                       | The browser is read-only; `index.md` generation is a later opt-in.                                             |
| Multi-bundle       | One bundle per invocation in v1; a registry is a later extension                                 | Keeps the cache and selector rules simple.                                                                     |

## 2. Package layout

```
packages/okf/
├── default.nix
├── go.mod
├── go.sum
├── main.go
├── cmd/
│   ├── root.go
│   ├── list.go
│   ├── show.go
│   ├── search.go
│   ├── facets.go        # types, tags, statuses, trust
│   ├── links.go         # links, backlinks, orphans, broken
│   ├── doctor.go
│   ├── index.go
│   ├── graph.go
│   ├── open.go
│   └── tui.go
└── internal/
    ├── frontmatter/     # tolerant YAML + line fallback
    ├── markdown/        # goldmark AST adapter: headings, links, fences
    ├── okf/             # Concept, Bundle, Source, Verification, Trust, Staleness
    ├── index/           # walk, parse, cache, incremental refresh
    ├── search/          # substring/exact/regex behind an interface
    ├── render/          # text, JSON, Markdown
    └── tui/             # bubbles/list + viewport + help + glamour
```

The module path is `okf` (like `kdn-certs` and `kdn-journal`). Go 1.25.2.

## 3. Data model

```go
type Bundle struct {
    Root      string
    Name      string
    Concepts  []*Concept
    Indexes   []*ReservedFile
    Logs      []*ReservedFile
    Issues    []Issue
}

type Concept struct {
    ID          string   // bundle-relative path without .md
    Path        string
    Bundle      string
    Type        string
    Title       string
    Description string
    Resource    string
    Tags        []string
    Status      string   // draft | stable | deprecated
    Generated   *Event   // by, at
    Verified    []Event  // by, at
    Trust       TrustTier
    StaleAfter  time.Time
    Stale       bool
    Sources     []Source
    Runtime     string   // Attested Computation
    Parameters  []Parameter
    Computation string
    Executor    *ResourceRef
    Attester    *ResourceRef
    Headings    []Heading
    Links       []Link
    Backlinks   []Link
    Body        []byte
    ModTime     time.Time
    Size        int64
    Issues      []Issue
}

type Link struct {
    Source   string // concept ID
    Target   string // raw target
    Resolved string // concept ID, or ""
    Kind     LinkKind // bundle-absolute | relative | external | fragment
    Broken   bool
    Line     int
}

type Source struct {
    ID           string
    Resource     string
    Title        string
    Author       string
    UsageCount   int
    LastModified time.Time
}

type Event struct {
    By string
    At time.Time
}

type TrustTier int // Unverified, MachineConfirmed, HumanReviewed
```

`Concept.ID` is the selector key. `Title` falls back to the first H1, then the file base name.
`Status` defaults to `stable`. `Stale` is `now >= StaleAfter` when `StaleAfter` is set.
`Generated` falls back to legacy `timestamp`; `Sources` falls back to a legacy `# Citations`
body list only for display, not for graph edges.

### 3.1 Progressive discovery

The discovery unit is a **section**, not a file. A large concept is read in widening steps:

1. `outline` — a bundle/directory/concept tree with headings and line ranges.
2. `section` — exactly one heading range, optionally capped.
3. `context` — a compact summary: title, frontmatter, heading tree, first paragraph per section.
4. `search` — hits point at a concept and a heading/line range, not a whole body.

```go
type Outline struct {
    ConceptID  string
    Title      string
    Headings   []HeadingNode
    Links      []LinkRef
    CodeBlocks []CodeBlock
    Tables     []TableRef
}

type HeadingNode struct {
    Level     int
    Text      string
    StartLine int // 1-based, inclusive
    EndLine   int // 1-based, inclusive
    Children  []HeadingNode
}

type Section struct {
    ConceptID string
    Heading   string
    StartLine int
    EndLine   int
    Markdown  string
}
```

- Line ranges are 1-based and inclusive; they are recomputed after an edit.
- `outline --depth N` caps the heading tree; the default is unlimited for one concept and 2 for a
  bundle tree.
- `section` returns the heading and its body up to the next heading of the same or a higher level;
  `--max-lines` truncates with an explicit marker.
- `context --budget N` fits a token/line budget; it prefers headings, descriptions and first
  paragraphs over full bodies.
- Goldmark supplies headings, links, tables and fenced code from the AST; a fence-aware line index
  supplies the exact source ranges. Frontmatter is parsed separately.
- `index.md` is read as a directory listing when present; the tool can synthesize the same view
  without writing a file.
- The CLI JSON is the v1 agent interface. An optional `atuin`-style MCP bridge can expose
  `okf_outline`, `okf_section` and `okf_search` later.
- Editing is out of scope for this layer: line ranges are read-only and never produced by a
  lossy Markdown renderer.

## 4. Index and cache

### 4.1 Walk

- Resolve the bundle root from `--bundle`, or walk up from cwd until a directory with `index.md`
  or at least one `.md` concept; require `--bundle` when ambiguous.
- Walk all `.md` files; skip hidden directories, `.git`, `.cache`, and entries in `.okfignore`
  (gitignore syntax, optional).
- Reserved files `index.md` and `log.md` are parsed separately and never become concepts.
- Do not follow symlinks outside the root; record a warning when a symlink is skipped.
- Read files concurrently with a small worker pool (default `GOMAXPROCS`, cap 8).

### 4.2 Cache

```
.cache/okf/<sha256(bundle-root)>/index-v1.json
```

The cache stores the bundle root, a format version, the walk generation, and one record per
concept: path, mtime, size, parsed frontmatter, headings, links, trust/staleness. A warm run
compares path+mtime+size and re-parses only changed files. `--rebuild` ignores the cache.
A cache version mismatch rebuilds; a corrupt cache is a warning and a rebuild, never a failure.
The cache never writes inside the bundle.

### 4.3 Link graph

- Parse links from the goldmark AST. Keep inline links and reference links; skip images.
- `Link.Kind`:
  - `bundle-absolute` for `/path`;
  - `relative` for `./`, `../`, or a bare path;
  - `external` for a URL with a scheme;
  - `fragment` for `#heading` or a link that resolves to the current concept.
- Resolve by stripping `#fragment` and `?query`, cleaning the path, and looking up the concept ID.
- A target outside the bundle is `external` with a warning; a missing target is `broken`.
- Build `Backlinks` by inverting the graph after all concepts are parsed.
- `orphan`: no backlinks and no incoming links. `missing-backlink`: A links to B but B does not link
  to A (a warning only, not an error).
- `--recursive` follows links breadth-first with a `--max-distance` cap.

## 5. Trust, freshness and facets

- Trust tier: no `verified` -> unverified; only non-`human:` actors -> machine-confirmed; any
  `human:` actor -> human-reviewed.
- `verified` accepts a list or a bare mapping. A malformed entry is a `verified-shape` issue, not a
  parse failure.
- `status` is `draft`, `stable` or `deprecated`; absent means `stable`; an unknown value is a
  warning.
- `stale_after` is parsed as an absolute timestamp; an unparseable value is a warning.
- Facets in the CLI and TUI: type, tag, status, trust, stale, orphan, broken.
- A concept with no optional family remains fully listable and showable.

## 6. CLI

Global flags: `--bundle`, `--json`, `--no-color`, `--width`, `--index <path>`, `--no-cache`.

| Command                                                    | Behaviour                                                                                                        |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `okf list`                                                 | Filter by type/tag/status/trust/stale/orphan/broken; sort by path/modified/title; `--limit`; `--json`.           |
| `okf show <concept>`                                       | Frontmatter summary, body, links, backlinks, trust and staleness; `--raw`, `--render`, `--json`, `--print-path`. |
| `okf search <query>`                                       | Title/description/tags/headings/body; `--regex`, `--exact`, `--scope`, `--limit`; `--json`.                      |
| `okf outline <bundle\|concept>`                            | Heading tree with line ranges, links, code blocks and tables; `--depth`; `--json`.                               |
| `okf section <concept> <heading>`                          | Exactly one heading range; `--max-lines`; `--json`.                                                              |
| `okf context <concept>`                                    | Budgeted summary plus heading tree and first paragraphs; `--budget`; `--json`.                                   |
| `okf types`, `okf tags`                                    | Facet counts, sorted; `--json`.                                                                                  |
| `okf links <concept>`                                      | Outgoing links; `--recursive`, `--max-distance`; `--json`.                                                       |
| `okf backlinks <concept>`                                  | Incoming links; `--json`.                                                                                        |
| `okf orphans`, `okf broken`, `okf stale`, `okf unverified` | Focused lists with the same filter flags.                                                                        |
| `okf doctor`                                               | Conformance issues with stable codes; `--parse-only`; `--json`; exit 1 on errors.                                |
| `okf graph`                                                | `--format json` or `dot`; nodes are concepts, edges are resolved links.                                          |
| `okf index`                                                | Build/refresh the cache; `--rebuild`; `--json` stats.                                                            |
| `okf open <concept>`                                       | `$EDITOR` hand-off; `--print-path` for composition.                                                              |
| `okf tui`                                                  | The interactive browser.                                                                                         |

Selectors: bundle-relative path, concept ID, exact title, unique title/ID prefix. Ambiguous
selectors exit 2 and list candidates. `--print-path` prints the resolved file.

## 7. TUI

### Layout

```
┌ header: bundle · tabs/facets · index state ┐
│ list (bubbles/list)  │ preview (viewport) │
│                      │ glamour Markdown   │
└ status · help (bubbles/help) ──────────────┘
```

- Left: `bubbles/list` over concepts. Each item shows type, title, status/trust/stale badges and a
  one-line description. Filtering is the list's built-in `/`.
- Right: `bubbles/viewport` with `glamour`-rendered Markdown. The document header shows type,
  concept ID, tags, status, trust, freshness, sources and verification.
- Footer: `bubbles/help` over `bubbles/key`.
- A `b` view replaces the preview with backlinks; `l` shows outgoing links; `esc` returns.
- A `t`/`g`/`s` prompt sets the type/tag/status filter; `u` cycles trust; `x` toggles stale.
- `o` opens the source in `$EDITOR`; `r` rebuilds the index; `q` quits.

### Rendering

Build a Markdown document from the model and render it with `glamour`
(`WithStandardStyle("dark")`, `WithWordWrap(width-2)`). The body comes from the concept file; the
header is synthesized. Use `lipgloss.SetHasDarkBackground(true)` before rendering so `lipgloss`
does not send an OSC 11 query that can leak into the shell.

### Fixed-height layout

The shell owns the header, status and footer; the list and viewport get `height - 3`. Every line is
truncated with `x/ansi` so ANSI styles do not break the width contract. This is the same layout
discipline `kdn-journal` uses.

## 8. JSON envelope

Every read command emits:

```json
{
  "schema_version": 1,
  "command": "list",
  "bundle": "/path/to/bundle",
  "generated_at": "2026-11-16T08:00:00+01:00",
  "data": {},
  "issues": []
}
```

`issues` is always an array. `root`/`generated_at` are not stable; do not diff them. Optional times
are omitted, never `0001-01-01`. `--json` ignores width and color. Shape tests cover each command;
byte-for-byte goldens are not used because the bundle path and generation time vary.

`data` payloads: `concepts` for `list`, `concept` for `show`, `hits` for `search` (each hit names a
concept and a heading/line range), `outline` for `outline`, `section` for `section`, `context` for
`context`, `threads`/`thread` for Atuin-backed reads, and `errors`/`warnings` counts for `doctor`.
Line ranges are 1-based and inclusive.

## 9. Doctor issue codes

| Code                                                         | Severity |
| ------------------------------------------------------------ | -------- |
| `frontmatter-missing`, `type-missing`, `type-not-string`     | error    |
| `index-reserved-shape`, `log-reserved-shape`                 | error    |
| `verified-shape`, `generated-shape`, `sources-shape`         | warning  |
| `status-invalid`, `stale-after-invalid`, `timestamp-invalid` | warning  |
| `duplicate-concept-id`, `concept-outside-bundle`             | error    |
| `computation-shape` (missing runtime/executor/attester)      | warning  |
| `broken-link`                                                | warning  |
| `missing-backlink`                                           | warning  |
| `orphan`                                                     | info     |
| `symlink-skipped`, `cache-corrupt`                           | warning  |

`--parse-only` exits 0 when every concept has parseable frontmatter and a non-empty `type`, even
when links are broken or optional families are absent. This is the CI/agent gate.

## 10. Search

Interface:

```go
type Searcher interface {
    Search(query Query) []Hit
}
```

v1: in-memory case-insensitive substring over title, description, tags, headings and body; an
`exact` mode for literal strings and a `regex` mode for RE2. v2: SQLite FTS5 or Bleve behind the
same interface, with the cache carrying an index version. The CLI must not change when the backend
changes.

## 11. Performance

- 1,000 concepts, 2 KB average: cold walk + parse under 2 s; warm cache under 200 ms.
- Worker pool for file reads; parse CPU-bound work can stay sequential in v1.
- Cache writes are atomic (temp file + rename), like `task set-status` in `kdn-journal`.
- A bundle with 100,000 concepts is a v2 target; the JSON cache and in-memory search may need
  streaming or SQLite then.

## 12. Tests

- `frontmatter`: invalid YAML fallback, quoted values, timestamps, unknown keys, CRLF.
- `markdown`: goldmark links/headings, reference links, images ignored, fences, nested links.
- `okf`: trust tiers, bare `verified` mapping, status default, stale boundary, legacy `timestamp`,
  Attested Computation shape.
- `index`: walk, reserved files, hidden/ignored dirs, symlinks, cache hit/miss/rebuild, concurrent
  reads, deterministic order.
- `links`: bundle-absolute, relative, fragments, external, broken, backlinks, orphans, recursive
  traversal.
- `render`: text width, JSON shape, `show` Markdown.
- `outline`/`section`/`context`: heading tree, exact line ranges, fence-aware boundaries, budget
  truncation, a 10,000-line fixture, and a section slice that does not read the whole body.
- `tui`: tabs/facets, list filtering, detail render, backlinks view, editor no-op, resize
  dimensions, non-TTY error.
- Integration: the real `docs/` tree, a synthetic 1,000-concept bundle, and a fixture with every
  issue code.
- Nix: `okf-test` and `okf-parse` (copy a fixture bundle into the sandbox and run
  `doctor --parse-only`).

## 13. Packaging

- `packages/okf/default.nix`: `buildGoModule`, shell completions, `passthru.tests.go-test`, version
  ldflags.
- `packages/default.nix`, `checks/default.nix`, `checks/bundles.nix`: the package and checks.
- `devenv.nix`: the binary on the shell PATH.
- Docs: `docs/okf-browser.md` (commands, JSON, TUI, trust/staleness), plus a short
  `.agents/rules/okf-browser.md` for agents, linked from `AGENTS.md`.

## 14. Migration and relationship to `kdn-journal`

- `okf` is independent; `kdn-journal` stays the journal/task tool.
- Copy the proven frontmatter fallback and the TUI layout discipline; do not import
  `kdn-journal/internal` across module boundaries.
- If both tools need the same parser later, extract a `packages/go/okf` module or merge them into
  one module with two commands. That is a separate task with its own acceptance.
- A later `kdn-journal` can gain an `--okf` view or read the OKF index; not in this task.

## 15. Open questions to settle before coding

1. Confirm `okf` as the final name; `kdn-okf` is the fallback if the repository wants the prefix.
2. Confirm the JSON cache for v1 and the threshold for moving to SQLite FTS5/Bleve.
3. Whether `.okfignore` is a file or a config key.
4. Whether the TUI needs a facet pane in v1 or prompts are enough.
5. Whether `okf show --render` uses `glamour` in-process or shells out to `glow`.
6. Whether `okf graph` emits Mermaid in addition to DOT/JSON.
