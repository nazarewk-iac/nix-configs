---
type: Solution
description: One OpenCode subagent per brys purpose alias, generated from hosts/brys/llm-routers.nix so the client follows the server. The raw-model qwen-*/ds4-* agents stay.
authored_by: agent
timestamp: 2026-10-27T07:25:00+01:00
---

# Solution: OpenCode sub-agent model routing

## What changed

- **`hosts/brys/llm-agents.nix`** (new) — a generator that reads
  `hosts/brys/llm-routers.nix`, inverts every model's `aliases` list into an
  `alias -> base model` map, keeps the purpose aliases
  (`<purpose>-<complexity>-<speed>[-...][-alt]`), and emits one opencode
  subagent per alias: `{ description; mode = "subagent"; model = "brys/<alias>"; }`.
  The alias set is read, never re-listed, so a server alias move reaches the
  client with no second edit.
- **`hosts/oams/devenv.nix`** — `kdn.opencode.settings.agent` is now
  `tierAgents // aliasAgents`: the existing raw-model `qwen-*`/`ds4-*` agents
  (one per base model and thinking level) plus the new purpose-alias agents.

## Result

`opencode agent list` shows 38 custom agents (30 purpose aliases + 8 raw-model).
Every alias agent maps to its own server id, for example
`chat-std-fast -> brys/chat-std-fast`, `vision-quick-fast -> brys/vision-quick-fast`.

Verified: `opencode run --model brys/tiny-quick-fast "call Task with
subagent_type='chat-dumb-fast'"` returned `PONG` from the `Chat-Dumb-Fast
Agent`, so the alias agents are invocable via the Task tool.

## How a caller uses them

Name the concrete alias as the `subagent_type`. The reason a family name
(`qwen-*`) failed in the test drive: the Task tool accepts only a real agent
name, and this build advertised just `explore`/`general` until a caller named a
custom one. Pick by intent:

- `tiny-dumb-fast`, `chat-dumb-fast` — mechanical extraction, classification.
- `chat-std-fast`, `tools-std-fast` — normal chat and tool calls.
- `code-std-fast`, `code-quick-fast` — coding.
- `reason-*`, `code-deep-slow`, `chat-deep-slow` — hard work.
- `vision-*` — image input. `audio-std-mid` — speech. `embed-*`/`rank-*` — retrieval.

See `.agents/skills/kdn-llms/SKILL.md` for the full intent table.

## Optional hardening (not applied)

To force an orchestrator onto only the cheap workers, add `permission.task` to
it: `{ "*": "deny", "chat-*": "allow", "code-*": "allow", "tiny-*": "allow" }`.
Not done: the alias set is large and the default (no gate) already works once a
caller names a concrete alias.

## Rejected alternatives

- **One agent per (base model, thinking level) for every model.** That explodes
  the count (dozens of models x 4 levels) and pins base ids in the client, which
  the alias scheme exists to avoid. The 8 raw-model agents remain for a caller
  that wants an explicit model.
- **Hard-coding the alias list in the client.** It would drift from
  `llm-routers.nix`. The generator reads the server's own attrset instead.
