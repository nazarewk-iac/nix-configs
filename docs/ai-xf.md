---
type: Reference
description: AI-XF v0.5 at Level 2 for the agent memory bundle — stable ids, typed links mirrored by body links, the manifest, the validator and the canonicaliser.
timestamp: 2026-11-16T15:45:00+01:00
---

# AI-XF

[AI-XF](https://github.com/DavidROliverBA/ai-xf-format) is a strict superset of OKF v0.2. Every
AI-XF bundle is a valid OKF bundle: an OKF-only reader sees the same files, an AI-XF-aware reader
sees more. The agent memory bundle at `.agents/knowledge` uses **Level 2 (AI-XF Full)**.

## What Level 2 adds

- **Stable identity.** Every concept carries an `id` that survives a file move or rename. The id
  is a simple slug; `/` is reserved for federation-qualified references.
- **Typed relationships.** A `links` entry names a `rel` and a `to`; the core vocabulary includes
  `depends-on`, `supersedes`, `contradicts`, `supports`, `describes` and their inverses.
- **Mirrored links.** Every same-bundle typed edge is also a plain Markdown body link, so an
  OKF-only reader still sees the untyped edge.
- **A manifest.** `manifest.ai-xf.yaml` declares `ai-xf: "0.5"` and `name`.
- **Trust signals.** The OKF fields the bundle already carries (`generated`, `verified`, `status`,
  `stale_after`) satisfy the Level 2 trust rule.
- **Well-formed media and contradiction state.** Not used yet; the seed has no binary assets or
  contradictions.

Level 3 (federation: namespaces, qualified cross-bundle links, shared vocabularies) is not used.
AI-XF v0.5 is a draft and v0.6 is proposed; the format is a published hypothesis, not a standard.

## Bundle fields

```yaml
---
type: Decision
title: Never push
description: The user reviews and pushes every change.
generated: { by: agent/cli, at: "2026-11-16T14:12:45Z" }
status: stable
id: no-push
links:
  - rel: relates-to
    to: path-scoped-jj
---
```

The body mirrors the typed edge:

```markdown
# Related Concepts

- [Path-scoped jj commands](path-scoped-jj.md): Both govern how an agent commits with jj.
```

`okf-memory update` preserves `id` and `links`; the validator catches a concept that loses them.

## Commands

```sh
ai-xf-validate .agents/knowledge --level 2
ai-xf-validate .agents/knowledge --level 2 --json
ai-xf-validate .agents/knowledge --stats
ai-xf-canon check .agents/knowledge   # canonical form, needs PyYAML
```

Exit codes: `0` pass, `1` findings at the requested level, `2` usage or load error.

`--stats` reports curation health (trust tiers, staleness, contradictions, per-claim citation
coverage, the Update : Creation ratio and freshness). It never affects pass/fail.

## Relationship to the other tools

- `okf-agent-memory` writes the concepts and preserves the AI-XF fields.
- `kdn-okf` reads the same bundle; it ignores `id` and `links` and follows the mirrored Markdown
  links, so the graph still works.
- `ai-xf-validate` is the Level 2 gate, next to `okf-memory validate --strict --drift`.
- The canonicaliser (`ai-xf-canon`) is available for a future database or importer; the memory
  bundle is not canonicalised yet.
