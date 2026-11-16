---
type: Rule
description: "Search the memory bundle before writing; one concept per decision; okf-agent-memory owns .agents/knowledge and kdn-okf only reads it."
timestamp: 2026-11-16T15:30:00+01:00
---

# Agent memory with `okf-agent-memory`

Full doc: [docs/okf-memory.md](../../docs/okf-memory.md). The bundle is `.agents/knowledge`,
reachable through the root `knowledge` symlink.

- **Search before write.** Run `okf-memory search "<query>" .agents/knowledge` or the
  `okf_search` MCP tool before proposing a decision or creating a concept.
- **One concept per decision.** A concept has one `type`, a one-sentence `description` and a short
  body. Do not duplicate a rule that already lives in `AGENTS.md`.
- **Bind constraints to code.** A rule about a path carries `code_refs`; query it with
  `--for-path` before editing that path.
- **No secrets, no transcripts, no personal data.** The bundle is committed.
- **One writer.** `okf-agent-memory` owns `index.md` and `log.md`; use `create`, `update` and
  `relate`. Do not hand-edit them, and do not run `kdn-okf generate-index` on this bundle.
- **`kdn-okf` reads, never writes.** Use it for `list`, `show`, `search`, `outline`, `section`,
  `context`, `tui` and `doctor --parse-only`.
- **Gate with `okf-memory validate .agents/knowledge --strict --drift`.** The scorecard is
  reported but not a hard gate until a human verifies the seed.
- **The symlink is the default.** From the repository root, `./knowledge` and `--scope project`
  resolve through `knowledge -> .agents/knowledge`; from a subdirectory, pass the path.
