# Basic Memory Knowledge Routing

Two knowledge bases are available as MCP backends:

- **memory-public** — open-source tooling, public Nix conventions, general engineering knowledge.
  Projects live under `~/.local/share/kdn-nix-configs/knowledge/public/`.
  Default project: `public/default`. Create new projects as siblings: `public/<project-name>/`.

- **memory-sensitive** — anything that should not be publicly disclosed: internal systems,
  credentials hints, employer-specific knowledge, internal architecture, work-specific tooling,
  internal configs. When in doubt about sensitivity, prefer sensitive.
  Projects live under `~/.local/share/kdn-nix-configs/knowledge/sensitive/`.
  Default project: `sensitive/default`. Create new projects as siblings: `sensitive/<project-name>/`.

## Routing rules

- Store in **memory-sensitive**: company names, internal hostnames, employee names, credentials,
  internal architecture, work-specific tooling, employer configs, anything marked confidential.
- Store in **memory-public**: Nix conventions, open-source package notes, public tooling workflows,
  general programming patterns, anything safe to publish.
- When a note spans both: split it — public facts in memory-public, sensitive context in
  memory-sensitive. Cross-link with a wikilink `[[note title]]`.

## OKF format

Always write notes in Open Knowledge Format (OKF):

- Frontmatter **must** include `type:` (e.g. `Reference`, `Playbook`, `Concept`, `Note`)
  and `description:` (one sentence).
- Optional but recommended: `tags:`, `timestamp:` (ISO 8601), `resource:` (URI if applicable).
- Body: use structural markdown (headings, tables, fenced code). Conventional sections:
  `# Schema`, `# Examples`, `# Citations`.
- basic-memory `## Observations` / `## Relations` syntax is compatible and may be added.

## Example frontmatter

```yaml
---
type: Reference
title: Some Tool Conventions
description: Key conventions for using some-tool in this project.
tags: [nix, tooling]
timestamp: 2026-06-24T00:00:00Z
---
```
