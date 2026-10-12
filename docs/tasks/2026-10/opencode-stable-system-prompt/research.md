---
type: Research
description: OpenCode 1.18.29 injects the date in the system prompt with no config toggle; the only hook is the v1 plugin experimental.chat.system.transform.
task: definition.md
authored_by: agent
timestamp: 2026-10-12T07:07:10+02:00
---

# Where OpenCode injects the date, and how to remove it

Researched against OpenCode version **1.18.29** (tag `v1.18.29` = commit
`16747470f976aca3d362ad730bcd3fe82ecc2c9a`), the version installed on oams.

## The injection site

`packages/opencode/src/session/system.ts:81`, in `SystemPrompt.environment()`:

```ts
environment: Effect.fn("SystemPrompt.environment")(function* (model: Provider.Model) {
  const ctx = yield* InstanceState.context
  ...
  return [
    [
      `You are powered by the model named ${model.api.id}. ...`,
      `Here is some useful information about the environment you are running in:`,
      `<env>`,
      `  Working directory: ${ctx.directory}`,
      `  Workspace root folder: ${ctx.worktree}`,
      `  Is directory a git repo: ${ctx.project.vcs === "git" ? "yes" : "no"}`,
      `  Platform: ${process.platform}`,
      `  Today's date: ${new Date().toDateString()}`,   // <-- the changing line
      `</env>`,
    ].join("\n"),
    ...
```

The block is assembled into the system prompt in
`packages/opencode/src/session/prompt.ts:1257-1269` (`sys.environment(model)`).

A second, newer path exists for OpenCode v2
(`packages/core/src/system-context/builtins.ts:33-39`, a `core/date` context with
`baseline: (date) => "Today's date: " + date`). It is not the default in
1.18.29.

## No config toggle

- `https://opencode.ai/config.json` has no date / environment / system-prompt
  key. `experimental` exposes only `disable_paste_summary`, `batch_tool`,
  `openTelemetry`, `primary_tools`, `continue_loop_on_deny`, `mcp_timeout`,
  `policies`.
- The 1.18.29 source schema (`packages/core/src/v1/config/config.ts`) matches:
  `instructions` only **adds** files; `experimental` has no date toggle.
- No `OPENCODE_*` flag relates to the date or the environment block
  (`packages/core/src/flag/flag.ts`).
- `agent.<name>.prompt` replaces the base provider prompt, but the environment
  block is still appended afterwards
  (`packages/opencode/src/session/llm/request.ts:60-66`).

**Verdict: the date injection is not configurable. A plugin is the only route.**

## The plugin hook

`packages/plugin/src/index.ts:291`, the `Hooks` interface:

```ts
"experimental.chat.system.transform"?: (
  input: { sessionID?: string; model: Model },
  output: { system: string[] },
) => Promise<void>
```

It runs in `packages/opencode/src/session/llm/request.ts:69`, right after the
system prompt is built:

```ts
const system = [
  [ ...(input.agent.prompt ? [input.agent.prompt] : SystemPrompt.provider(input.model)),
    ...input.system,
    ...(input.user.system ? [input.user.system] : []),
  ].filter((x) => x).join("\n"),
]
yield* input.plugin.trigger(
  "experimental.chat.system.transform",
  { sessionID: input.sessionID, model: input.model },
  { system },
)
```

`system` is an array with one joined string. The plugin may mutate it, so it can
delete the `Today's date:` line.

The hook is **not** in the public docs; it is in the shipped type definitions and
is invoked by the CLI. It is `experimental`, so it can change. OpenCode v2
replaces it with `ctx.session.hook("context", ...)`.

## Loading a plugin

OpenCode auto-loads `{plugin,plugins}/*.{ts,js}` from `.opencode/` and
`~/.config/opencode/` (`packages/opencode/src/config/plugin.ts:18-30`). The
`kdn.llm-client` aspect already writes
`.opencode/plugins/kdn-llm-session-id.ts` this way, so the same mechanism
carries the new plugin.

There is no per-plugin `enabled` flag in v1. A plugin is disabled by removing
its file, or all external plugins are disabled with `OPENCODE_PURE=1` /
`--pure`.

## The skill the prompt points at

The replacement line names the `current-date` skill, so the model can obtain the
date on demand.

- **Location and format:** `.opencode/skills/<name>/SKILL.md`, YAML frontmatter
  with required `name` and `description`. The directory name must equal `name`
  (`^[a-z0-9]+(-[a-z0-9]+)*$`, 1-64 chars).
- **Discovery:** `packages/opencode/src/skill/index.ts` scans project
  `.opencode/skills/`, global `~/.config/opencode/skills/`, and the
  Claude/agent-compatible `.claude/skills/` and `.agents/skills/`. Symlinks are
  followed, so a devenv `files."...".text` entry works.
- **Injection:** the system prompt gets only each skill's **name, description
  and location** (`Skill.fmt(list, { verbose: true })` in `session/system.ts`),
  sorted by name. The **full body is not in the system prompt**; the `skill`
  tool returns it as a tool result. So the listing is stable across days, and
  the skill does not reintroduce a date into the prompt.

## References

- Upstream: `github.com/anomalyco/opencode` `v1.18.29`, files
  `packages/opencode/src/session/system.ts`,
  `packages/opencode/src/session/llm/request.ts`, `packages/plugin/src/index.ts`.
- `modules/den/aspects/opencode.nix`, `modules/den/aspects/llm-client.nix` — the
  generators in this repository.
