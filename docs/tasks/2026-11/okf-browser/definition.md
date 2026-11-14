---
type: Task
description: Build a general-purpose CLI and TUI that indexes, searches, validates and browses any Open Knowledge Format v0.2 bundle, with trust, freshness and link graph as first-class views.
status: open
authored_by: agent
timestamp: 2026-11-16T08:00:00+01:00
---

# OKF browser: a general-purpose index and TUI for OKF bundles

## Context

`kdn-journal` solved the repository's task and agent-journal problem. It is deliberately specific:
its commands speak of sessions, tasks, boards and worklogs, and its parser knows the task
frontmatter contract. The generic pieces underneath — tolerant YAML frontmatter, a fence-aware
Markdown scanner, a stable JSON envelope, a `doctor --parse-only` gate and a charmbracelet TUI —
are reusable, but the tool as a whole is not a general document browser.

The repository already uses [Open Knowledge Format](../../../okf-format.md) for docs, tasks, rules and
agent journals. The canonical specification is now **OKF v0.2** in
[`GoogleCloudPlatform/open-knowledge-format`](https://github.com/GoogleCloudPlatform/open-knowledge-format).
A bundle is a directory of Markdown files with YAML frontmatter; `type` is the only required key;
`index.md` and `log.md` are reserved; links are ordinary Markdown links; and v0.2 adds provenance
(`sources`), trust (`generated`, `verified`), lifecycle (`status`, `stale_after`) and Attested
Computation metadata.

The owner wants a **dedicated general-purpose tool** for browsing and indexing OKF documents. It
should work on any OKF v0.2 bundle, not only this repository, and it should expose the knowledge
graph and trust signals that plain `cat`, `grep` and `glow` cannot answer together.

## Goal

One binary that answers, for any OKF bundle:

- what concepts exist, by type, tag, status, trust tier, freshness and path;
- what one concept says, rendered, with its frontmatter and body;
- what it links to, what links back, what is orphaned and what is broken;
- where it came from, who generated it, who verified it and whether it is stale;
- what changed, from `log.md` and file activity;
- what is malformed, from a conformance check;
- the same answers as stable JSON for agents and scripts.

Plus a TUI that makes the same model browsable: list, filter, preview rendered Markdown, follow
links and backlinks, and open the source in `$EDITOR`.

Target: one screen, under a second for a warm index, no manual `cat`/`grep` chains.

## Scope

### 1. Bundles and concepts

- Discover one or more bundle roots, including a bundle nested in a larger repository.
- Walk every non-reserved `.md` file; parse YAML frontmatter and Markdown body.
- Treat `index.md` and `log.md` as reserved files, not concepts.
- Tolerate a concept with only `type`; tolerate unknown keys and unknown `type` values.
- Keep a stable **concept ID**: the bundle-relative path without `.md`.
- Skip hidden directories, `.git`, `.cache`, and a configurable ignore list.
- Do not follow symlinks outside the bundle by default.

### 2. Frontmatter and OKF v0.2 fields

Index the required and recommended fields, plus the v0.2 families:

| Family      | Fields                                                                                               |
| ----------- | ---------------------------------------------------------------------------------------------------- |
| Identity    | `type`, `title`, `description`, `resource`, `tags`                                                   |
| Provenance  | `sources[]` with `id`, `resource`, `title`, `author`, `usage_count`, `last_modified`; `usage_window` |
| Trust       | `generated.by`, `generated.at`, `verified` (list or bare mapping)                                    |
| Lifecycle   | `status` (`draft`, `stable`, `deprecated`), `stale_after`                                            |
| Computation | `runtime`, `parameters`, `computation`, `executor`, `attester` on `type: Attested Computation`       |
| Legacy      | `timestamp` as a fallback for `generated.at`                                                         |

Derive a **trust tier** from `verified`: unverified, machine-confirmed, or human-reviewed.
Derive **staleness** from `stale_after` and the current time. Do not reject a concept for a missing
optional family.

### 3. Links and the graph

- Extract standard Markdown links from the body. Ignore images and external URLs for the graph.
- Resolve bundle-absolute links (`/tables/customers.md`) against the bundle root and relative
  links against the concept's directory.
- Strip fragments and query strings before resolving; keep the original target for display.
- Record outgoing links, backlinks, orphan concepts, missing backlinks and broken links.
- Treat a broken link as a warning, never a parse failure: OKF explicitly allows not-yet-written
  targets.
- Export the graph as JSON and Graphviz DOT.

### 4. Index

- Build an in-memory index of concepts, links, backlinks, tags, types, sources and trust/freshness.
- Persist a cache outside the bundle (`.cache/okf/<bundle-hash>.json` or equivalent).
- Incremental refresh by path, mtime and size; `--rebuild` forces a full walk.
- Keep the index format versioned; a version mismatch rebuilds.
- Search the title, description, tags, headings and body. Start with case-insensitive substring
  and an exact/regex mode; design the backend so a full-text engine can replace it.
- Do not write into the bundle in v1.

### 5. CLI shape

Working name: `okf` (package `packages/okf`). If the repository prefers its `kdn-` prefix,
`kdn-okf` is an alias; decide before packaging.

```
okf list [--bundle PATH] [--type T] [--tag T] [--status S] [--trust T]
         [--stale] [--orphan] [--broken] [--sort path|modified|title]
         [--limit N] [--json]
okf show <concept> [--bundle PATH] [--json] [--raw] [--render]
okf search <query> [--type T] [--tag T] [--status S] [--regex]
           [--limit N] [--json]
okf types [--bundle PATH] [--json]
okf tags [--bundle PATH] [--json]
okf links <concept> [--recursive] [--json]
okf backlinks <concept> [--json]
okf orphans [--bundle PATH] [--json]
okf broken [--bundle PATH] [--json]
okf stale [--bundle PATH] [--json]
okf unverified [--bundle PATH] [--json]
okf doctor [--bundle PATH] [--parse-only] [--json]
okf graph [--bundle PATH] [--format json|dot]
okf index [--bundle PATH] [--rebuild] [--json]
okf open <concept> [--bundle PATH] [--editor]
okf tui [--bundle PATH]
okf version
```

Global flags: `--bundle`, `--json`, `--no-color`, `--width`, `--root`/`--bundle` discovery.

The CLI should compose with `fzf`, `jq`, `rg` and `$EDITOR`; every read command has `--json`.
`--print-path` should resolve a concept for editor integration.

### 6. TUI shape

Use the charmbracelet stack that already works in `kdn-journal`:

- `bubbles/list` for concepts, filtering, pagination and the status bar.
- `bubbles/viewport` + `glamour` for the rendered Markdown preview.
- `bubbles/help` + `bubbles/key` for the footer.
- `lipgloss` for layout; `x/ansi` for ANSI-aware truncation.

Views:

- **Documents**: list with type, title, description, status, trust and stale badge.
- **Preview**: rendered frontmatter summary and body; links are visible.
- **Backlinks**: reverse links for the selected concept.
- **Links**: outgoing links, resolved or broken.
- **Facets**: type, tag, status, trust and stale filters.
- **Search**: `/` fuzzy filter; `s` full-text search; `t` type; `g` tag; `b` backlinks; `l` links;
  `o` editor; `r` reindex; `q` quit.

Keep the fixed-height layout and the explicit dark background so `lipgloss` does not leak an OSC 11
query into the shell.

### 7. Conformance and doctor

`doctor` validates OKF v0.2 conformance and reports stable issue codes:

- `frontmatter-missing`, `type-missing`, `type-not-string`;
- `index-reserved-shape`, `log-reserved-shape`;
- `verified-shape`, `generated-shape`, `sources-shape`;
- `status-invalid`, `stale-after-invalid`, `timestamp-invalid`;
- `duplicate-concept-id`, `concept-outside-bundle`;
- `broken-link` (warning), `missing-backlink` (warning), `orphan` (info);
- `computation-shape` for an Attested Computation missing `runtime`/`executor`/`attester`.

`--parse-only` is the gate for Nix and agents: it exits 0 when every concept parses, even when
links are broken or optional fields are absent.

## Relationship to `kdn-journal`

`kdn-journal` stays the journal/task-specific tool. This task does **not** migrate it. It should
reuse the lessons and, where practical, the proven parser code:

- tolerant YAML fallback for the real unquoted `: ` descriptions;
- fence-aware Markdown scanning;
- stable JSON envelope and exit codes;
- `doctor --parse-only` as a clean gate;
- charmbracelet TUI with `bubbles/list`, `viewport`, `help`, `key`, `glamour`;
- real-repository integration tests.

A later task can extract a shared Go library or make `kdn-journal` a journal-specific front end over
the OKF index. Do not couple the two in this task.

## Acceptance

- `okf index` walks a synthetic 1,000-concept bundle in under 2 seconds cold and under 200 ms warm
  on the development host; `--rebuild` is deterministic.
- Every existing OKF document in this repository indexes without a parse error.
- `okf list`, `okf show`, `okf search`, `okf links`, `okf backlinks`, `okf orphans`, `okf broken`
  and `okf doctor --parse-only` work against a fixture bundle and this repository.
- A fixture bundle proves: bundle-absolute and relative links, fragments, external URLs, broken
  links, backlinks, orphan detection, `index.md`/`log.md` exclusion, unknown types, missing
  optional fields, invalid YAML fallback, and trust/staleness derivation.
- `--json` has a stable envelope and shape tests; `doctor` exit codes are 0/1/2.
- The TUI opens, filters by type/tag/status/trust, previews rendered Markdown, follows a link and a
  backlink, opens `$EDITOR`, and quits cleanly.
- `nix build .#okf` and the package check succeed; `go test ./...` passes inside and outside Nix.
- `devenv.nix` exposes the binary.

## Out of scope

- Authoring or editing concepts; writing `index.md`/`log.md` into the bundle.
- Executing or attesting Attested Computations.
- A web UI, SSH server, sync, or VCS integration.
- A terminal graph layout; export DOT/JSON and let Graphviz or a browser render it.
- Migrating `kdn-journal` onto the new index.

## Open questions

1. **Name and package**: `okf` / `packages/okf`, or `kdn-okf` / `packages/kdn-okf`?
2. **Index backend**: JSON cache plus in-memory search for v1, or SQLite FTS5 / Bleve from the
   start? The 1,000-document target is small; the 100,000-document target is not.
3. **Parser reuse**: copy the proven `kdn-journal` parsers, extract a shared module, or make both
   tools one module with two commands?
4. **Multiple bundles**: one bundle per invocation, or a registry of bundle roots?
5. **Link semantics**: should a relative link that escapes the bundle root be a warning, an error,
   or an external path?
6. **Graph**: is DOT export enough, or does the TUI need a backlinks-only graph view first?
7. **Index location**: `.cache/okf/`, XDG cache, or a sidecar next to the bundle?
8. **Generated `index.md`**: read-only synthesis in v1, or an opt-in writer later?
