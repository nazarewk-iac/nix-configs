---
type: Research
description: What Pi actually provides for multi-agent work, from its own shipped docs — the absence of built-in sub-agents, the two documented delegation routes, per-run model and tool control, file sessions, and the RPC/SDK surfaces.
task: definition.md
authored_by: agent
timestamp: 2026-10-27T22:50:00+01:00
---

# Research: Pi, read from its own documentation

Sources: the packaged tree
`/nix/store/…-pi-coding-agent-0.85.1/lib/node_modules/pi-monorepo/docs/`, and the
installed CLI (`pi --version` → **1.1.0**; `pi --help`). Quoted lines are verbatim
from those docs.

## 1. What it is

`pkgs.pi-coding-agent`, binary `pi`: an "AI coding assistant with read, bash,
edit, write tools". TypeScript. It has extensions, skills, prompt templates, MCP
servers, themes, and session files.

The relevant CLI surface, verbatim from `pi --help`:

| Flag | Meaning |
|---|---|
| `--model <pattern>` / `--provider <name>` | per-run model, `provider/id`, optional `:<thinking>` suffix |
| `--thinking <level>` | `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max` |
| `--models <patterns>` | comma-separated patterns for interactive cycling |
| `--mode <text\|json\|rpc>` | output mode; **`rpc`** is the programmatic one |
| `--print`, `-p` | non-interactive: process the prompt and exit |
| `--session <path\|id>`, `--session-id <id>`, `--fork <id>`, `--continue` | session identity and forking |
| `--tools`, `--exclude-tools`, `--no-tools`, `--no-builtin-tools` | per-run tool allowlist/denylist, with patterns |
| `--system-prompt`, `--append-system-prompt` | per-run prompt control (repeatable) |
| `--extension -e <path\|builtin:name>`, `--skill`, `--prompt-template` | load resources explicitly |
| `--export <file>` | export a session to HTML |
| `--approve` / `--no-approve` | trust or ignore project-local files |

So the primitives a coordinator needs — per-agent model, per-agent thinking, per-agent
tools, resumable sessions, machine-readable output — all exist as flags.

## 2. Sub-agents are **not** built in, by design

Verbatim, `docs/usage.md`:

> It intentionally does not include built-in MCP, sub-agents, permission popups,
> plan mode, to-dos, or background bash. You can build or install those workflows
> as extensions or packages, or use external tools such as containers and tmux.

This is the central fact. Delegation in Pi is something you build, and the docs
say so in the same breath as the feature list.

## 3. The two documented delegation routes

### (a) An extension that spawns sub-agents

`docs/extensions.md` lists a built-in extension category:

> `subagent/` — Spawn sub-agents — `registerTool`, `exec`

So the supported pattern is: register a tool, and in its handler `exec` a child
`pi` process (or any command). That gives **process-per-agent**, which is exactly
the isolation that makes per-agent models trivial: each child gets its own
`--model`, `--thinking` and `--tools`.

Trade-off: each child is a cold start, and on `brys` a cold model load is
30–120 s. Persistent workers would need either a warm model kept resident by the
router or an in-process design.

### (b) The SDK, several agents in one process

`docs/sdk.md`:

> The SDK provides programmatic access to pi's agent capabilities. […] **Example
> use cases:** […] Build custom tools that spawn sub-agents

```typescript
import { createAgentSession, ModelRuntime, SessionManager } from "@earendil-works/pi-coding-agent";
const modelRuntime = await ModelRuntime.create();
const { session } = await createAgentSession({
  sessionManager: SessionManager.inMemory(),
  modelRuntime,
});
session.subscribe((event) => { … });
```

That is an embeddable agent loop with an event stream — the same shape as
opencode's server API, but in TypeScript and in-process. It keeps models warm
inside one runtime and makes the supervisor's view easy: one event stream.

Trade-off: the orchestrator and the workers share a process, so a crash or a
runaway loop takes them all; and the "one process" isolation that a subprocess
gives is gone.

## 4. What a reviewer role looks like

The advisor in the target workflow must **see** work and **not act**. With the
flags above that is a run with `--tools` limited to read-only entries (or
`--no-builtin-tools` plus a read tool), a strong model, and a high thinking level.
Sessions are files, so a review can be a `--fork` of the orchestrator's session —
the reviewer sees the whole plan and transcript without a hand-written summary.
That is a genuinely better primitive than opencode's model for this role, where a
subagent receives only what the caller pastes into the prompt.

## 5. Local fleet access

`docs/llama-cpp.md` and `docs/providers.md` are the relevant pages. The repository
already registers `brys` as an OpenAI-compatible provider for opencode with
discovery (`kdn.llm.client` + `discovery.enable`), and the compat proxy is what
translates DSML tool calls. For Pi the requirement is the same: a provider entry
pointing at the proxy, with the alias ids as model names. **Not yet probed** — the
task's first concrete step.

Note the asymmetry: opencode's agent aliases are generated from
`hosts/brys/llm-routers.nix`, so the client follows the server. Pi would need an
equivalent generator, or a manual provider list that can drift.

## 6. What Pi has that opencode does not

| Primitive | Why it matters for this workflow |
|---|---|
| `--mode rpc` | the supervisor drives the orchestrator as a process, not by typing into a TUI |
| file sessions + `--fork` | a reviewer can read the real transcript; a run can be replayed |
| per-run `--tools` | a hard guarantee that the reviewer cannot write |
| in-process SDK | several agents and warm models in one runtime |
| `--export` to HTML | a transcript artifact per agent, for the evaluation |

## 7. What opencode has that Pi does not

- Built-in sub-agents with a declared `subagent_type` per purpose alias, already
  generated from the router config.
- A working, tested integration with this repository's devenv, skills, and the
  `/tmp/opencode` conventions.
- An established harness in
  [../gaz-den-workstation/design.md](../gaz-den-workstation/design.md) and three
  written host tasks that assume it.

## 8. Version divergence, worth flagging

The CLI on PATH reports **1.1.0**; the store path resolved for the package is
**0.85.1**. So the deployed binary and the packaged tree inspected here are not the
same build. Any conclusion about a specific flag must be re-checked against the
version actually used.

## 9. Cost estimate, as a hypothesis to test

- Extension route: one TypeScript file registering a `delegate` tool, spawning
  `pi -p --model <alias> --thinking <level> --tools <list> --session-id <child>`
  and returning stdout. Small.
- The hard parts are not the spawn: they are (a) deciding what the child sees,
  (b) collecting its result into the parent's context without flooding it, and
  (c) stopping a child that loops. Those are the same three problems the opencode
  harness solved with a watch loop and a tool-result truncation rule.

## 10. Not verified

- Whether `builtin:` extension names include `subagent` in the version in use.
- Whether Pi can point at the compat proxy and use a purpose alias id unchanged.
- Whether `--mode rpc` is stable enough to supervise for hours.
