---
type: Task
description: Cut the context a sub-agent and a small agent load before they see a task, and replace a fixed docs table with on-demand frontmatter discovery.
status: open
authored_by: agent
timestamp: 2026-11-03T13:00:01+01:00
---

# Minimize agent context and add progressive discovery

## Context

A sub-agent pays for boilerplate before it sees its task. Measured on 2026-11-03 from a live Pi
request (`tokens_evaluated: 6870`, `cache_n: 6855`):

| part                                     | tokens     | note                    |
| ---------------------------------------- | ---------- | ----------------------- |
| **AGENTS.md** (project_context)          | **~3,770** | 55% of the prompt       |
| addendum (`data/pi/AGENTS.md` + catalog) | ~1,100     | injected by the wrapper |
| pi-orchestrator allow-list + fleet block | ~400       |                         |
| docs + rules + preamble/tools            | ~500       |                         |
| task                                     | rest       |                         |

Inside AGENTS.md, 10,609 of its 15,088 chars (about 2,650 tokens) are the **`docs/` table**, and
it duplicates the `## Topic Files` list. The table is a navigation aid, not an instruction.

Consequence measured in the same run: 9 of 23 delegations failed, 3 with
`400 … request (17043/18061 tokens) exceeds … (16384)`. A 16k child spends about 45% of its
window on this boilerplate.

A `CLAUDE.md` sits next to `AGENTS.md`, so confirm there is no double load. There is not: Pi
returns the **first** existing file per directory from
`["AGENTS.override.md","AGENTS.md","AGENTS.MD","CLAUDE.md","CLAUDE.MD"]`
(`resource-loader.js:116`), so with `AGENTS.md` present `CLAUDE.md` is never read.

## Goals

1. A sub-agent loads only what its task needs. Target: **about 500 tokens** of shared system
   prompt for a surgical child, **0** for an isolated one.
2. The parent keeps the full AGENTS.md, because it owns commits and policy.
3. Documentation becomes **discoverable on demand** from frontmatter, not carried inline.
4. Nothing generated drifts: the index is read live, or generated at build time.

## Design

### A. Trim the sub-agent prompt with spawn flags, not an override file

`AGENTS.override.md` cannot be sub-agent only: Pi finds context files by `cwd` and walks
ancestors, and children run in the same directory as the parent. Use the spawn arguments in
`packages/pi-coding-agent-extensions/subagent/index.ts` instead:

```
--no-context-files --no-skills --no-prompt-templates
--append-system-prompt <bundled subagent-rules.md>
--append-system-prompt <agent systemPrompt>
```

- `--no-context-files` drops AGENTS.md (about 3,770 tokens).
- `--no-skills` drops the skill index (about 770 tokens).
- A per-agent `context: full` frontmatter key opts an agent back in when it needs the repo rules
  (for example a `worker` that runs `jj`).

Related work already in place: `isolated: true` on the `editor` agent, and the `pi-hashline-edit`
extension. Both stay.

**Where the harness actually spawns children (verified 2026-11-03).** The orchestrator's `delegate`
comes from **pi-orchestrator**, not this repo's `subagent` extension. `delegate.ts` spawns children
with `--mode rpc` and appends `--append-system-prompt`, but passes **no** `--no-context-files` and
no `--no-skills`, so a harness child still loads AGENTS.md (about 3.8k tokens). pi-orchestrator's
config accepts `childExtensions` and `childBlockedTools`, but **no context flag and no extra
argument**. Therefore the harness fix is one of:

- **done**: forked pi-orchestrator as `nazarewk-iac/pi-orchestrator` (branch
  `nazarewk-iac/child-context`). It reads `PI_ORCHESTRATOR_CHILD_MINIMAL=1` and then spawns a child
  with `--no-context-files --no-skills --no-prompt-templates`, skips parent-prompt forwarding, and
  appends a compact rules block. The policy is config-driven (`childContext`: auto by provider/model,
  `fullAgents` opt-out); the env var is only an override. See [docs/pi-extension-forks.md](../../pi-extension-forks.md).

The `subagent` extension change here is still correct and useful for anything that calls the
`subagent` tool directly; it does not reach the orchestrator's `delegate` path.

### B. A compact shared rules file

`data/pi/subagent-rules.md`, about 40 lines: simple technical English, one exact task, do not run
`jj` unless told, report the file and line range and the parse result. This replaces 3,770 tokens
with about 400. It holds only rules that apply to every child.

### C. Progressive discovery tool

One read-only tool, `frontmatter_index`, over any tree:

```
frontmatter_index { roots: ["docs", ".agents/rules"], match?: "zfs|rag", type?: "Task|Design" }
→ path<TAB>type<TAB>description
```

- Reads `type:` and `description:` from frontmatter. Pi frontmatter is simple, so `rg` on the
  frontmatter block is enough; `gray-matter` is the library option if a parser is preferred.
- **Reads live. No generated file**, so there is nothing to keep in step. If an embedded index is
  ever wanted, generate it at build time in Nix (`devenv files.` or a package), never commit it.
- Filters by `match`, `type`, and roots; caches by directory mtime.
- Add a second step: `doc_fetch { path }` returns one document, so the shape is
  list then fetch, the same as the session tools.
- Reuse across kinds: the same tool scans `data/pi/agents/`, `.agents/skills/`, and
  `docs/tasks/**/definition.md`, so "which agent, skill or task covers X" is one call.
- Add a `tags:` frontmatter field to make routing queryable, not only free text.
- The RAG task (`local-rag-index`) can reuse this scan as its `kind=note` source.

### D. Trim AGENTS.md

- Remove the duplication between `## Topic Files` and the `docs/` table (one list only).
- Compress each row to path plus one short clause, or drop the table and point at `index.md` /
  `frontmatter_index`.
- Tighten the prose (the STE rule already applies). Several blocks are two to three times longer
  than needed.
- Target: AGENTS.md about 3,770 to about 1,000 tokens, with the docs table removed from the
  prompt entirely.

### E. Adopt OKF as the document schema (not ad-hoc frontmatter)

The repo already has an OKF rule: `.agents/rules/okf-format.md` and [docs/okf-format.md](../../okf-format.md).
OKF (Open Knowledge Format) is Google's vendor-neutral convention for knowledge as markdown plus
YAML frontmatter, in a directory tree. Verified against upstream
(`GoogleCloudPlatform/knowledge-catalog/okf/README.md`, 2026-11-03):

- **Required**: a small set of keys; in practice a non-empty `type:`. Extra keys must be tolerated
  by every consumer.
- **Recommended, queryable**: `title`, `description`, `resource`, `tags`, `timestamp`. v0.2 adds
  trust and freshness keys (`sources`, `generated`, `verified`, `status`, `stale_after`); add them
  only if a checker enforces them.
- **Reserved filenames**: `index.md` (directory listing) and `log.md` (date-grouped history). They
  carry their own structure and are exempt from the ordinary document rules.
- OKF is explicitly designed for **agents ingesting files into context**, so it is the right
  schema for what this task indexes.

So `frontmatter_index` reads OKF keys, and the check validates OKF conformance.

### F. Progressive discovery: OKF `index.md` plus a live index tool

Upstream states the property directly: OKF has "**progressive disclosure built in** —
auto-generated `index.md` files let an agent navigate the hierarchy one level at a time instead of
loading the entire bundle into context."

Two ways to use that, and this task does both:

1. **`frontmatter_index`** (live, no artifact) for cross-tree queries by `type`/`tags`/`match`.
   Nothing to keep in step.
2. **Generated `index.md`** per directory, in the OKF format
   (`* [Title](url) - description`), produced at **build time** (Nix `devenv files.` or a package)
   and never committed, so it cannot drift. An agent reads the nearest `index.md` first, then the
   one document it needs.

### G. OKF conformance check (and optional Vale for prose)

A small checker validates the OKF rules that matter for discovery:

- every non-reserved `.md` has parseable YAML frontmatter with a non-empty `type:`;
- `description:` is one short phrase;
- reserved `index.md`/`log.md` are exempt and, if generated, match the OKF entry format.

This replaces "Vale for STE" as the enforcement mechanism. Vale (`nixpkgs`, 3.17.1) stays optional
for prose style; the OKF check is what keeps the index valid and terse.

## Caveats learned during this work

- **`AGENTS.override.md` is scoped by `cwd`**, so it affects the parent too. Use it only when the
  whole workspace should change, not to separate a child from its parent.
- **Local models make real tool calls only through `--mode json`** (the subagent path). In
  `--print` text mode, `qwen3.5-4b` prints the call as text and `lfm2.5-24b` prints raw
  `<|tool_call_start|>` tokens. Test tool behaviour through `delegate`, not a one-shot.
- **A colon inside an unquoted frontmatter value breaks extension load.** `description: … Isolated:
no …` is invalid YAML and took down pi-orchestrator (and with it the whole extension). Quote the
  value or remove the colon. Vale should catch this class.
- **`~/.pi/agent/agents/` is a one-time copy, not a symlink.** Edit the repo copy and sync it, or
  the installed agents drift.

## Acceptance

- A normal sub-agent prompt is measured at or below about 1,500 tokens (`tokens_evaluated` on a
  `--no-tools` run through the subagent path); an isolated one at or below about 600.
- `frontmatter_index` returns a compact list for `docs/`, `.agents/rules/`, and
  `docs/tasks/**/definition.md`, with a `match` filter.
- `docs/` table is gone from the loaded prompt; AGENTS.md carries a one-line pointer instead.
- Vale runs as a check and passes on `docs/` (or reports a bounded, accepted rule set).
- Before and after prompt sizes are recorded in this task.

## Out of scope

Semantic retrieval (that is `local-rag-index`). Editing tools (already added: `pi-hashline-edit`
and the `editor` agent).
