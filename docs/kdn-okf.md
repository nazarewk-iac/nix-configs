---
type: Reference
description: The kdn-okf CLI and TUI that index, search and browse Open Knowledge Format v0.2 bundles — commands, JSON and JSONL output, selectors, trust and freshness, doctor codes and the TUI keys.
timestamp: 2026-11-16T14:30:00+01:00
---

# `kdn-okf`

`kdn-okf` indexes an [Open Knowledge Format v0.2](okf-format.md) bundle, exposes the concept list,
the link graph, trust and freshness as a CLI and a TUI, and reads a large concept in slices
(`outline`, `section`, `context`) instead of loading the whole body. It is a Go binary under
[`packages/kdn-okf/`](../packages/kdn-okf/).

## Why

`kdn-journal` answers the task and agent-journal questions of this repository. `kdn-okf` is the
general tool: any directory of Markdown files with YAML frontmatter is a bundle, `type` is the only
required key, and `index.md` and `log.md` are reserved. It answers what concepts exist by type,
tag, status, trust and freshness; what links to what; what is stale, unverified, orphaned or
broken; and what changed.

## Commands

```
kdn-okf list [--type T] [--tag T] [--status S] [--trust T]
             [--stale] [--orphan] [--broken] [--unverified]
             [--sort path|title|modified|type|status|trust|stale]
             [--limit N] [--all]
kdn-okf show <concept> [--raw] [--render] [--include-body]
kdn-okf search <query...> [--regex] [--exact] [--scope title|heading|body|all]
                          [--type T] [--tag T] [--status S] [--limit N]
kdn-okf outline [<bundle|concept>] [--depth N]
kdn-okf section <concept> <heading> [--max-lines N]
kdn-okf context <concept> [--budget N]
kdn-okf types | tags | statuses | trust
kdn-okf links <concept> [--recursive] [--max-distance N]
kdn-okf backlinks <concept>
kdn-okf orphans | broken | stale | unverified
kdn-okf doctor [--parse-only] [--ignore <code>]
kdn-okf graph [--format json|dot]
kdn-okf index
kdn-okf generate-index [--dry-run] [--force] [--check]
kdn-okf open <concept>
kdn-okf tui
kdn-okf skill [--dir <path>]
kdn-okf version
kdn-okf completion <shell>
```

Global flags: `--bundle <dir>`, `--json`, `--jsonl`, `--no-color`, `--width <n>`,
`--cache-dir <path>`, `--no-cache`, `--rebuild`, `--quiet`, `--now <RFC3339>`, `--prefix`,
`--print-path`.

`--bundle` defaults to a walk up from the current directory to the nearest directory with
`index.md`; when none exists, the nearest directory with a `.md` file is the bundle. A file
argument is refused.

`orphans`, `broken`, `stale` and `unverified` are `list` with a preset filter: they share one
`concepts` payload and accept the same filter flags.

## Selectors

A selector resolves in this order: exact concept ID (a leading `/` and a trailing `.md` are
stripped), exact bundle-relative or absolute path, exact frontmatter `title` or first H1. A prefix
needs `--prefix` and must be unique. An unknown selector exits 2; an ambiguous selector lists the
candidates on stderr and exits 2, so stdout stays empty for `$(kdn-okf show x --print-path)`.

`--print-path` is available on `show`, `outline`, `section`, `context`, `links`, `backlinks` and
`open`. It prints one absolute path and nothing else, and it wins over `--json`.

## Output

Text is the default. `--json` prints one envelope:

```json
{
  "schema_version": 1,
  "command": "list",
  "bundle": "/path/to/bundle",
  "generated_at": "2026-11-16T14:30:00+01:00",
  "data": { "concepts": [], "index": {}, "total": 0 },
  "issues": []
}
```

`--jsonl` prints one JSON object per line and no envelope, for `jq`, `fzf` and `xargs`:

```sh
kdn-okf list --jsonl | jq -r '[.id, .type, .title] | @tsv'
kdn-okf search needle --jsonl | jq -r '.concept_id'
kdn-okf doctor --jsonl | jq -r 'select(.severity=="error") | .code'
```

`list` emits one `conceptSummary` per line (`id`, `path`, `rel_path`, `type`, `title`,
`description`, `tags`, `status`, `trust`, `stale`, `stale_after`, `modified`, `size`). `show`
emits one full concept. `search` emits one hit per line (`concept_id`, `path`, `rel_path`,
`heading`, `level`, `start_line`, `end_line`, `snippet`). `links`/`backlinks` emit one link per
line. `doctor` emits one issue per line. The other commands emit one object. Issues and warnings
stay on stderr in JSONL mode.

Empty arrays are `[]`, never `null`. Trust, status and link kinds are kebab-case strings.

## Progressive discovery

- `outline` prints a heading tree with 1-based inclusive line ranges. `--depth N` caps it; the
  default is unlimited for one concept.
- `section` returns exactly one heading range. A heading resolves by exact text, then a unique
  case-insensitive prefix; `--max-lines` truncates with an explicit marker and `truncated: true`.
- `context` fits a line budget: header, heading tree and the first paragraph of each section.
  `--budget` counts lines, not tokens, so the output is deterministic.
- `search` hits name a concept and a heading range, never a whole body. A line belongs to its
  deepest enclosing heading.

## Trust, freshness and the graph

- `trust` is derived from `verified`: no entry is `unverified`, only non-`human:` actors is
  `machine-confirmed`, any `human:` actor is `human-reviewed`.
- `stale` is true when `stale_after` is in the past. `--now` pins the clock.
- Links resolve bundle-absolute (`/x.md`) from the bundle root and relative links from the
  concept's directory; fragments and queries are stripped before resolution. A missing target is
  `missing: true` and a `broken-link` warning, never a parse failure.
- `backlinks` invert the graph; `orphans` are concepts with no incoming links.

## Generating `index.md`

The browser is read-only by default. `generate-index` is the explicit writer: it writes one
deterministic `index.md` in every directory that holds concepts, the bundle root included.

- The file carries `generated: true` and a `<!-- generated by kdn-okf; do not edit -->` marker, a
  table of the direct concepts (type, status, trust, title) and links to the child directories.
- No timestamps: a second run is byte-identical, so it never churns the VCS.
- A human-authored `index.md` is refused. `--force` overwrites it.
- `--check` exits 1 when a generated index is missing or stale, for CI.
- `--dry-run` prints the plan and writes nothing.
- `index.md` stays reserved, so the generated files never become concepts.

`--jsonl` emits one entry per directory with `dir`, `path`, `action` (`write`, `update`,
`unchanged`, `refuse`, `missing`, `stale`) and an optional `reason`.

## Doctor

`doctor` reports stable codes: `frontmatter-missing`, `frontmatter-invalid`, `type-missing`,
`type-not-string`, `verified-shape`, `status-invalid`, `stale-after-invalid`, `broken-link`,
`missing-backlink`, `orphan`, `computation-shape`, `cache-write`.

`doctor` exits 1 when an `error` remains. `doctor --parse-only` is the gate: it reports only
`frontmatter-missing`, `type-missing`, `type-not-string`, `duplicate-concept-id`,
`concept-outside-bundle` and the reserved-file shape codes, and exits 1 only for those. Broken
links, missing backlinks, orphans, absent optional families and a corrupt cache never fail the
gate. `--ignore <code>` drops a known finding.

## TUI

`kdn-okf tui` needs a terminal. It uses `bubbles/list`, `bubbles/viewport`, `bubbles/help`,
`bubbles/key`, `glamour` and `lipgloss`.

| Key       | Action                                                        |
| --------- | ------------------------------------------------------------- |
| `j`/`k`   | Move in the list.                                             |
| `enter`   | Open the full preview.                                        |
| `esc`     | Leave the full preview, then the links view, then the filter. |
| `/`       | Fuzzy filter.                                                 |
| `f`       | Cycle the status facet.                                       |
| `u`       | Cycle the trust facet.                                        |
| `x`       | Toggle the stale facet.                                       |
| `s` / `S` | Sort forward / backward.                                      |
| `c`       | Clear every filter and the sort.                              |
| `l` / `b` | Show outgoing links / backlinks.                              |
| `v`       | Return to the preview.                                        |
| `o`       | Open the source in `$EDITOR`.                                 |
| `r`       | Reindex.                                                      |
| `q`       | Quit.                                                         |

Statuses are filled chips (`◇ draft`, `◆ stable`, `⊘ deprecated`); a `NO_COLOR` terminal keeps the
glyph and the word. The header shows the active facets, the sort and the bundle name. Below 72
columns the list takes the whole width and `enter` opens the preview.

## Exit codes

0 success (including an empty result), 1 `doctor` findings, 2 usage, unknown flag, unknown or
ambiguous selector, or a non-TTY `tui`.

## JSONL in the other tools

`kdn-journal` and `kdn-jj-meta` also accept `--jsonl`:

```sh
kdn-journal tasks --jsonl | jq -r '[.slug, .status] | @tsv'
kdn-journal session changes --jsonl | jq -r '.change_id'
kdn-jj-meta list --jsonl | jq -r 'select(.missing|length>0) | .change_id'
kdn-jj-meta check --jsonl | jq -r 'select((.errors|length)>0) | .change_id'
```

`kdn-jj-meta attribute --jsonl` emits one object per change with `added`, `skipped` and `written`.
`kdn-journal session backfill --jsonl` emits one object per change with a `state` field:
`attributed`, `unchanged`, `skipped` or `failed`.
