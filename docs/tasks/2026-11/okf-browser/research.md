---
type: Research
description: OKF v0.2 essentials and the CLI/TUI shapes worth borrowing from zk, nb, glow, Obsidian-style vault tools and the OKF reference visualizer.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T08:00:00+01:00
---

# Research: OKF v0.2 and document-browser shapes

## 1. OKF v0.2 in one page

Source: [GoogleCloudPlatform/open-knowledge-format](https://github.com/GoogleCloudPlatform/open-knowledge-format),
[SPEC.md](https://github.com/GoogleCloudPlatform/open-knowledge-format/blob/main/SPEC.md). The
repository's [okf-format.md](../../../okf-format.md) is a v0.1 summary; v0.2 is the current contract.

| Concern              | Rule                                                                                                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Bundle               | A directory tree of Markdown files; the unit of distribution.                                                                                                                                                 |
| Concept              | One non-reserved `.md` file. Its **concept ID** is the bundle-relative path without `.md`.                                                                                                                    |
| Required key         | `type` (non-empty string). Everything else is optional.                                                                                                                                                       |
| Recommended keys     | `title`, `description`, `resource`, `tags`.                                                                                                                                                                   |
| Reserved files       | `index.md` (directory listing) and `log.md` (date-grouped history); never concepts.                                                                                                                           |
| Links                | Standard Markdown links; bundle-absolute (`/tables/x.md`) or relative (`./x.md`). Broken links are allowed.                                                                                                   |
| Provenance           | `sources[]` entries with `id`, `resource`, `title`, optional `author`, `usage_count`, `last_modified`; `usage_window`.                                                                                        |
| Trust                | `generated: { by, at }`; `verified` as a list or a bare mapping. Trust tier: unverified, machine-confirmed, human-reviewed.                                                                                   |
| Lifecycle            | `status: draft \| stable \| deprecated` (absent = stable); `stale_after` is an absolute instant.                                                                                                              |
| Actors               | `<producer>/<version>`, `human:<id>`, `process:<id>`. Trust keys off the `human:` prefix.                                                                                                                     |
| Attested Computation | A `type: Attested Computation` concept with `runtime`, optional `parameters`, `computation`, `executor`, `attester`. The browser indexes and displays this; it does not execute it.                           |
| Conformance          | Every non-reserved `.md` has parseable frontmatter with a non-empty `type`; reserved files follow their shapes. Unknown keys, unknown types, missing optional families and broken links must not be rejected. |
| Versioning           | A bundle-root `index.md` may declare `okf_version: "0.2"`; consumers fall back best-effort on unknown versions.                                                                                               |
| v0.1 fallbacks       | `timestamp` stands in for `generated.at`; a body `# Citations` list stands in for `sources`.                                                                                                                  |

The reference visualizer demonstrates the consumption shape: a force-directed graph, a detail panel
with frontmatter and rendered Markdown, a "Cited by" backlinks list, a search box (title, concept
id, tags), a type filter, and graph layouts. That is a useful checklist for the TUI and graph
export, not a requirement to render a graph in the terminal.

## 2. Tools worth borrowing from

| Tool                                                                             | Shape                                                                                                 | What to borrow                                                                                                                                                                                                                                                                            |
| -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`zk`](https://github.com/zk-org/zk)                                             | Go CLI + SQLite index; `zk list`, `edit`, `graph`, `tag list`, `link`, `--interactive` via `fzf`      | The filter vocabulary: `--match` with `fts`/`exact`/`re`, `--tag`, `--linked-by`/`--link-to` (outgoing/backlinks), `--orphan`, `--broken-links`, `--missing-backlink`, `--related`, `--mentioned-by`, `--limit`, `--sort`, `--interactive`. This is the closest single model for the CLI. |
| [`nb`](https://github.com/xwmx/nb)                                               | Bash CLI + local web/terminal browser; `ls`, `show`, `search`, `browse`, tags, links, Git sync        | The list/show/search/browse split, excerpts, editor hand-off, and a browser that is a first-class surface rather than an afterthought.                                                                                                                                                    |
| [`glow`](https://github.com/charmbracelet/glow)                                  | Markdown reader; no-arg TUI, CLI render, pager, width, styles                                         | The Markdown-first TUI and the `glow -w`, `-p`, `-s` flags. The TUI should feel like a reader, not a file manager.                                                                                                                                                                        |
| [`notesmd-cli`](https://github.com/Yakitrak/notesmd-cli) (formerly Obsidian CLI) | Go CLI over a vault; `open`, `search`, `search-content --format json`, `list`, `print`, `frontmatter` | Vault selection, `--format json`/`--no-interactive` for scripting, editor flag, frontmatter read/edit. It proves that a headless vault CLI is useful without the GUI.                                                                                                                     |
| Obsidian / Logseq / Foam / org-roam                                              | GUI/editor knowledge bases                                                                            | Backlinks and graph are the primary navigation model; tags and aliases are facets. The TUI needs a backlinks view even if it has no graph view.                                                                                                                                           |
| OKF reference visualizer                                                         | Static HTML + Cytoscape.js                                                                            | Graph + detail + "Cited by" + search + type filter is the complete consumer shape. DOT/JSON export is enough for v1; the TUI can show backlinks and links without a canvas.                                                                                                               |
| `ripgrep`, `fzf`, `jq`                                                           | Unix composition                                                                                      | Every read command should emit stable JSON and line-oriented paths so these tools can compose. `--interactive` is a thin `fzf` hand-off, not a second UI.                                                                                                                                 |

## 3. Lessons from `kdn-journal`

The first tool produced reusable evidence:

- **Tolerant frontmatter is not optional.** Seven real task definitions carry an unquoted `: ` in
  `description`; a strict YAML parser hides them. Parse, fall back to a line reader, and report a
  warning.
- **A fence-aware Markdown scanner is the base.** Headings, bullets, tables and links inside code
  fences must not become structure. `kdn-journal` already has the scanner and tests for it.
- **Real-repository tests catch what fixtures miss.** Date-headed `item | state` tables, free-form
  boards, invalid YAML and 4,499-file artifact directories only appeared in the real tree.
- **JSON is a contract, not a debug print.** `schema_version`, `command`, `root`, `generated_at`,
  `data`, `issues`, explicit exit codes 0/1/2, and shape tests made the tool usable by agents.
- **`doctor --parse-only` is a clean gate.** Default validation can fail on pre-existing findings;
  the parse-only path is what CI and agents can require.
- **Charmbracelet components are the right TUI base.** `bubbles/list` (filter/pagination/status),
  `bubbles/viewport`, `bubbles/help`/`key`, `glamour` and `lipgloss` gave a complete browser
  without custom scroll and filter code.
- **Do not let the terminal background query leak.** `lipgloss` adaptive colors send OSC 11; set an
  explicit dark background before rendering so a late response cannot print after the TUI exits.
- **Activity is not mtime.** `generated.at` (or legacy `timestamp`) is stable across checkouts;
  mtime is a fallback and a tie-breaker.
- **Selectors need one rule.** Path, concept ID, title and unique prefix; ambiguous input exits 2
  with the candidates.
- **Do not walk expensive artifact trees.** `kdn-journal` learned to read only top-level journal
  files for `LastTouched`; an OKF browser must still walk `.md` files, but should skip hidden,
  ignored and cache directories and cap the walk.

## 4. Design inputs

- Use **goldmark** (already in the dependency graph through `glamour`) to extract headings, links
  and code fences from the body. It is more reliable than a second regex parser and gives source
  positions for `doctor`.
- Use the proven **frontmatter** parser shape, with a line fallback and `FrontmatterError`.
- Start with a **JSON index cache** and in-memory search. 1,000 concepts do not justify SQLite FTS5;
  keep the search backend behind an interface so `zk`-style FTS can arrive later.
- Make **trust, status and staleness** filters first-class in both CLI and TUI. They are the
  difference between a generic Markdown browser and an OKF browser.
- Make **backlinks** a first-class view. It is the cheapest graph feature and the one readers use
  most.
- Keep **DOT/JSON graph export** in v1; a terminal graph canvas is not worth the complexity.
- Keep `kdn-journal` separate. Share parsers only if the duplication becomes painful; do not turn
  this task into a refactor of the working journal tool.

## 5. Sources

- OKF v0.2 specification:
  <https://github.com/GoogleCloudPlatform/open-knowledge-format/blob/main/SPEC.md>
- OKF reference agent and visualizer:
  <https://github.com/GoogleCloudPlatform/open-knowledge-format>
- `zk` filtering and links:
  <https://zk-org.github.io/zk/notes/note-filtering.html>
- `zk` repository: <https://github.com/zk-org/zk>
- `nb` repository: <https://github.com/xwmx/nb>
- `glow` repository: <https://github.com/charmbracelet/glow>
- `notesmd-cli` repository: <https://github.com/Yakitrak/notesmd-cli>
