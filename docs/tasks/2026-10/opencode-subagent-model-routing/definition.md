---
type: Task
description: Make an OpenCode orchestrator delegate to the cheap local sub-agents instead of the slow frontier model. A custom subagent is invocable by Task only when its name is a valid subagent_type and the caller's permission.task allows it; a subagent with no explicit model inherits the caller's model. Register one subagent per brys purpose alias.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-27T06:42:39+01:00
---

# OpenCode sub-agent model routing (purpose aliases)

> ✅ **Done** — see the solution in [done.md](done.md).

## Context

A test drive ran a slow orchestrator (`brys/orchestrate-deep-slow`,
qwen3.8-flash-next, ~2.5-4 t/s) and asked it to delegate work to the local
sub-agents `qwen-*` and `ds4-*`. It did not. Instead it spawned the built-in
`@explore` and `@general` sub-agents, and every one of those streamed the
**orchestrator's own slow model** (`providerID=brys modelID=orchestrate-deep-slow`).
A one-task job then cost about eight hours at the slowest possible rate.

## Findings (measured 2026-10-27, OpenCode 1.19.0)

1. **Custom agents are loaded and are subagent-mode.**
   `opencode agent list` shows all eight: `qwen-high/low/medium/off` and
   `ds4-high/low/medium/off`, each `mode: subagent`, each with an explicit
   `model` in `opencode.jsonc`.

2. **The Task tool CAN invoke them by name.** Verified live:
   `opencode run --model brys/tiny-quick-fast "<call Task with
subagent_type='qwen-low'>"` printed `Qwen-Low Agent` then `PONG`. So a
   custom `subagent_type` works; it is not limited to `explore`/`general`.

3. **The failure was a naming/discovery gap, not a hard limit.** In the test
   drive the orchestrator's prompt named the families (`qwen-*`, `ds4-*`) but
   not a concrete `subagent_type`, and the Task tool's advertised list in that
   session showed only `explore` and `general`. The model therefore used the two
   built-ins it was shown.

4. **A subagent with no `model` inherits the caller's model.** OpenCode docs,
   Agents > Model: "subagents will use the model of the primary agent that
   invoked the subagent". The built-in `explore`/`general` set none, so they ran
   the slow orchestrator model. The custom `qwen-*`/`ds4-*` set an explicit
   `model`, so they run cheap.

5. **`permission.task` is the control knob.** OpenCode docs, Agents > Task
   permissions: a `permission.task` map on the **caller** agent gates which
   subagents the model may invoke, by glob, last-rule-wins. `deny` removes the
   subagent from the Task tool description entirely, so the model cannot pick
   it.

## Goal

A slow orchestrator delegates its cheap, mechanical sub-tasks to `qwen-*` and
its harder ones to `ds4-*`, and never silently runs the slow model for a
sub-task.

## Proposed approach

1. Add an orchestrator primary agent to `opencode.jsonc` (or `modules/slots/`
   source) with an explicit `permission.task`:
   `{ "*": "deny", "qwen-*": "allow", "ds4-*": "allow" }`, plus the frontier
   model. The model then sees, and can call, only the cheap families.
2. In any orchestrator job spec, name the concrete `subagent_type` per task
   ("use `qwen-low` for extraction, `qwen-high` for reasoning") — a family name
   is not a valid type.
3. Confirm the routing in the server log: a delegated sub-task must stream
   `modelID=qwen3.8-flash-next`, not `modelID=orchestrate-deep-slow`.

## Open questions

- Does a `permission.task` allowlist change the Task tool's advertised
  `subagent_type` list in the schema the model reads, or only the accept/reject
  gate? Verify with a run that logs the tool schema.
- Should `explore`/`general` be pinned to a cheap model in `opencode.jsonc`, so
  a caller that forgets to name a custom type still gets the cheap model?
- Is there a way to make the _default_ sub-agent choice cheap without editing
  every caller?

## References

- `opencode.jsonc` — the eight custom subagents and their `model` fields.
- OpenCode docs, Agents: Types, Model, Task permissions, Hidden.
- `docs/tasks/2026-10/zellij-llm-opencode/` — the driver used to spawn and watch
  the orchestrator.
- The test drive: a slow orchestrator ran `@explore`/`@general` on its own
  model, ~8 h for one RustDesk deploy task (2026-10-26/27).
