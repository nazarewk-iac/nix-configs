---
type: Rule
description: Requires OKF-conformant YAML frontmatter (type/description/timestamp) on markdown files.
timestamp: 2026-07-10T15:00:00+02:00
---

# Open Knowledge Format (OKF)

Full doc: [docs/okf-format.md](../../docs/okf-format.md)

Every markdown file you create or substantially edit in this repo (or a downstream repo using
this rule) must carry YAML frontmatter with at least a `type:` key — the only required OKF field.
Add `description:` (one sentence) and `timestamp:` (ISO 8601, from `git log -1 --format=%aI --
<file>` when available) alongside it. Reuse existing `type:` values already present in nearby
files rather than inventing new ones per file.

Exceptions:
- A repo's public GitHub-facing root `README.md` may be left frontmatter-free — GitHub renders
  raw YAML as visible text on `.md` files, unlike Jekyll front-matter-aware pages.
- Files with their own required frontmatter contract (e.g. Claude Code `SKILL.md`'s
  `name:`/`description:`) keep those keys; add `type:`/`timestamp:` alongside, don't replace.
- Reserved OKF filenames `index.md`/`log.md` follow their own structure (no frontmatter, or a
  date-grouped log) — see the full doc.
