---
type: Research
description: Every part of the OpenCode 1.18.29 system prompt, marked stable or volatile across requests in the same repo, to maximise prefix reuse.
task: definition.md
authored_by: agent
timestamp: 2026-10-12T07:40:00+02:00
---

# Which system-prompt parts change, and which stay stable

Researched against OpenCode **1.18.29**. The prompt is one joined string: the
provider/agent prompt, then the `<env>` block, then the instructions, then the
MCP instructions, then the skills listing, then a per-message `user.system`
(`packages/opencode/src/session/llm/request.ts:58-68`). It is placed as the first
message, so the whole string is the cacheable prefix
(`request.ts:100-113`).

## Stability table (two requests, same repo, same session)

| Part | Source | Stable? | Why it changes |
|---|---|---|---|
| Agent/provider prompt | `request.ts:60`, `system.ts:27-49` | volatile across turns | `agent.prompt` replaces it, and the agent switches (plan/build) per message |
| `<env>`: cwd, worktree, vcs, platform | `system.ts:77-80` | **stable** | fixed for the session |
| `Today's date` | `system.ts:81` | **volatile** (daily) | `new Date().toDateString()` — **handled by the plugin** |
| Model name / exact model ID | `system.ts:74` | stable per model | changes only if the model changes |
| `<available_references>` | `system.ts:84-101` | stable | sorted; changes only if references are added/removed |
| Instructions (AGENTS.md / CLAUDE.md / CONTEXT.md **content**) | `instruction.ts:155-169` | **volatile** | the file **content is re-read every request**; editing AGENTS.md changes the prefix |
| MCP instructions | `system.ts:117-133` | stable normally | changes if a server reconnects or its `instructions` text is dynamic |
| Skills listing (name + description) | `system.ts:105-114`, `skill/index.ts:310-347` | stable | sorted by name; changes only if skill files or frontmatter change |
| `STRUCTURED_OUTPUT_SYSTEM_PROMPT` | `prompt.ts:1271` | volatile | only when a message asks for `json_schema` output |
| Per-message `user.system` | `request.ts:62`, `prompt.ts:668` | volatile | per-message custom system prompt |
| Plugin `experimental.chat.system.transform` additions | `request.ts:70-83` | volatile | arbitrary plugin output |
| `MAX_STEPS_PROMPT` (assistant message) | `prompt.ts:1281` | volatile | only on the last allowed step |
| Plan-mode / build-switch reminders | `prompt.ts:1235`, `reminders.ts` | volatile | synthetic parts in the last user message |

## What this means for the same repo

- **The date is the only daily breaker.** The plugin removes it. Nothing else in
  the `<env>` block changes for a fixed repo and session.
- **The instruction content is the next breaker.** OpenCode re-reads and
  re-injects the whole `AGENTS.md` on **every** request
  (`instruction.ts:155-169`). This repo edits `AGENTS.md` (and `.agents/rules/`)
  while working, so each edit moves the prefix and forces a re-prefill. The
  instructions sit **after** the `<env>` block, so the `<env>` prefix still
  matches; only the bytes from the first changed instruction line onward are
  re-processed.
- **The skills listing is stable.** It is sorted and carries only name and
  description, so adding a skill changes it once, then it is fixed.
- **Agent switching** (plan vs build) swaps the leading provider/agent prompt,
  which moves the very first bytes. A session that stays in one agent avoids it.
- **Model switching** changes the `You are powered by the model named …` line
  near the top of the `<env>` block.

## Recommendations

1. Keep the date out (done).
2. Treat `AGENTS.md` and `.agents/rules/` as prompt content: an edit is a
   prefix change. Prefer to edit them at a natural boundary (start of a turn),
   not mid-turn, and expect the next request to re-prefill from the first
   changed line.
3. Do not switch the agent or the model mid-conversation if prefix reuse
   matters.
4. The skills listing, MCP instructions and the `<env>` block are stable; leave
   them alone.

## References

- `packages/opencode/src/session/prompt.ts:1257-1286`,
  `packages/opencode/src/session/llm/request.ts:58-113`,
  `packages/opencode/src/session/system.ts:27-133`,
  `packages/opencode/src/session/instruction.ts:98-169`,
  `packages/opencode/src/skill/index.ts:310-347`.
- [hybrid-reuse.research.md](../llm-warm-start-session/hybrid-reuse.research.md)
  — why a moved prefix forces a full re-prefill on the hybrid model.
