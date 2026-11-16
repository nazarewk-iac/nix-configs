---
type: Reference
description: The writable agent memory bundle at .agents/knowledge — okf-agent-memory, the knowledge symlink, the one-writer rule, MCP tools, validation and the scorecard.
timestamp: 2026-11-16T15:30:00+01:00
---

# Agent memory: `.agents/knowledge`

`okf-agent-memory` keeps persistent project memory as an OKF v0.2 bundle. It is the writable side
of the OKF tooling in this repository; `kdn-okf` reads the same bundle and never writes it.

## Layout

```
knowledge -> .agents/knowledge        # tracked symlink
.agents/knowledge/
├── index.md                          # okf_version: "0.2", scopes: [project]
├── log.md                            # maintained by okf-agent-memory
└── decisions/
    ├── index.md                      # generated listing with descriptions
    ├── no-push.md
    ├── path-scoped-jj.md
    ├── one-writer-per-bundle.md
    ├── cache-outside-bundle.md
    └── trailer-profiles.md
```

The tool's default bundle path is `./knowledge` or `.`, relative to the current directory. From
the repository root the symlink makes `./knowledge` resolve to `.agents/knowledge`; without it the
tool would treat the whole repository as a bundle. `--scope project` is also `./knowledge/`, so it
needs the symlink too. From a subdirectory, pass the path or run from the root.

## Commands

```sh
okf-memory init .agents/knowledge
okf-memory create <concept-id> .agents/knowledge --type Decision --title "…" --desc "…" --body "…"
okf-memory update <concept-id> .agents/knowledge --desc "…"
okf-memory relate <source> <target> .agents/knowledge --desc "…"
okf-memory search "<query>" .agents/knowledge --limit 3 --json
okf-memory search --for-path <path> .agents/knowledge --json
okf-memory show <concept-id> .agents/knowledge --json
okf-memory validate .agents/knowledge --strict --drift
okf-memory validate .agents/knowledge --scorecard
okf-memory mcp .agents/knowledge
```

`create` and `update` maintain the parent `index.md` and `log.md`; `relate` adds a link between two
concepts. `--for-path` finds the concepts whose `code_refs` govern a file, which is the check to
run before editing it.

## One writer per bundle

- `okf-agent-memory` owns `index.md` and `log.md` in `.agents/knowledge`. Use `create`, `update`
  and `relate`; do not hand-edit those two files.
- `kdn-okf` reads the bundle: `list`, `show`, `search`, `outline`, `section`, `context`, `tui` and
  `doctor --parse-only`.
- `kdn-okf generate-index` is for documentation bundles such as `docs/`. Do not run it on the
  memory bundle; two writers would fight over the same listings.

## MCP

The devenv shell registers one backend:

```json
{
  "okf-memory": {
    "command": "<okf-agent-memory>/bin/okf-memory mcp <repo>/.agents/knowledge"
  }
}
```

Read tools: `okf_search`, `okf_show`, `okf_validate`. Write tools: `okf_create`, `okf_update`,
`okf_relate`. The write tools are enabled only for a memory-writing role; the seed is reviewed
before agents add to it.

## AI-XF Level 2

The bundle also conforms to [AI-XF](ai-xf.md) Level 2: every concept carries a stable slug `id`
and typed `links` entries mirrored by a body link, and `manifest.ai-xf.yaml` declares the version
and name. The gate is `ai-xf-validate .agents/knowledge --level 2`. `kdn-okf` ignores the extra
fields and follows the mirrored links. Level 3 (federation) is not used.

## Validation and scorecard

Two gates run together:

- `okf-memory validate .agents/knowledge --strict --drift` fails on a broken link, an orphan, or a
  description that no longer matches the parent `index.md` listing.
- `ai-xf-validate .agents/knowledge --level 2` fails on a missing or duplicate `id`, a typed link
  without a body mirror, or a missing manifest.

The scorecard reports three pillars: epistemic maintenance, human stewardship and graph integrity.
The seed scores 72/100 (Grade C) because no concept carries a human `verified` entry. The check
therefore gates on `--strict --drift`, not `--min-score 80`. Once the first batch is reviewed by a
human, add `verified: [{ by: "human:<name>", at: "<iso-time>" }]` and raise the gate.

## Security

- `scopes: [project]`; no vendor registry, user or system layers in v1.
- The hub/vault (zero-knowledge sync) is off.
- No secrets, credentials, customer data or session transcripts.
- `code_refs` are repository-relative.
- The bundle is committed, so every change is reviewable with `git diff`.

## Relationship to the other tools

| Tool               | Owns                                                |
| ------------------ | --------------------------------------------------- |
| `okf-agent-memory` | the writable memory bundle and its MCP server       |
| `kdn-okf`          | the read-only browser, TUI and structural validator |
| `kdn-journal`      | the task and session journals                       |
| `kdn-jj-meta`      | the jj commit trailers                              |
