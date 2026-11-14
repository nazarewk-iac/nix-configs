---
type: Reference
description: Open Knowledge Format summary as applied to this repository, with a pointer to the current v0.2 specification and its new trust, provenance and lifecycle fields.
timestamp: 2026-11-16T08:00:00+01:00
---

# Open Knowledge Format (OKF)

> **OKF v0.2 is current.** The canonical specification now lives at
> [GoogleCloudPlatform/open-knowledge-format](https://github.com/GoogleCloudPlatform/open-knowledge-format/blob/main/SPEC.md).
> This file is a v0.1 summary kept for the repository's existing frontmatter convention. The v0.2
> additions — `sources`, `generated`, `verified`, `status`, `stale_after`, Attested Computation
> metadata and the actor convention — are summarized in
> [docs/tasks/2026-11/okf-browser/research.md](tasks/2026-11/okf-browser/research.md).

Spec source: [GoogleCloudPlatform/knowledge-catalog okf/](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf).

OKF is a minimalist standard for representing knowledge as a directory of markdown files with
YAML frontmatter — human-readable, agent-parseable, version-control-friendly.

## Conformance (required)

Every non-reserved `.md` file must have parseable YAML frontmatter containing a non-empty
`type:` key. `type` values are producer-defined (not centrally registered) — reuse a small,
consistent set of values across similar files rather than inventing one per file.

## Recommended frontmatter (priority order)

| Key           | Purpose                                                                 |
| ------------- | ----------------------------------------------------------------------- |
| `title`       | Human-readable display name (often redundant with an `# H1` or `name:`) |
| `description` | One-sentence summary                                                    |
| `resource`    | URI uniquely identifying the underlying asset                           |
| `tags`        | YAML list for cross-cutting categorization                              |
| `timestamp`   | ISO 8601 datetime, typically last-modified                              |

Producers may add arbitrary extra keys; consumers must tolerate unknown keys. Files that already
carry mechanism-specific frontmatter (e.g. a Claude Code `SKILL.md`'s `name:`/`description:`, or
a rule file's `paths:` glob) keep those keys as-is — add OKF keys alongside them, don't duplicate
or replace.

## Body conventions

Favor structural markdown (headings, lists, tables) over prose. Conventional section headings:

| Heading       | Purpose                                        |
| ------------- | ---------------------------------------------- |
| `# Schema`    | Structured description of asset columns/fields |
| `# Examples`  | Concrete usage examples in code blocks         |
| `# Citations` | External sources supporting claims             |

## Cross-linking

- Absolute (bundle-relative): starts with `/`, relative to bundle root — recommended.
- Relative: standard markdown relative paths — what this repo uses today.

## Reserved filenames

- `index.md` — directory listing, no frontmatter, entries as `* [Title](url) - description`.
- `log.md` — optional chronological change history, date-grouped (`YYYY-MM-DD`), newest first.

This repo has no `index.md`/`log.md` files today; if added later, follow the reserved-filename
structure above rather than treating them as ordinary concept documents.
