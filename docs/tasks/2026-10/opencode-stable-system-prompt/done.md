---
type: Solution
description: A guarded OpenCode v1 plugin (written by the kdn.opencode aspect/slot) strips the injected `Today's date:` line from the system prompt, so the prefix is stable and the local llama-server reuses its cache across midnight.
task: definition.md
authored_by: agent
timestamp: 2026-10-12T07:10:00+02:00
---

# Solution — a stable OpenCode system prompt

## Root cause analysis

OpenCode 1.18.29 appends an `<env>` block to the system prompt. The last line is
`Today's date: <date>` (`packages/opencode/src/session/system.ts:81`). The date
changes at midnight, so the prompt prefix changes. A local llama-server cannot
reuse the cached prefix, and on the hybrid Qwen model the divergence is before
the first context checkpoint, so llama.cpp re-processes the whole conversation
(see [../llm-warm-start-session/hybrid-reuse.research.md](../llm-warm-start-session/hybrid-reuse.research.md)).

There is **no config option and no environment variable** to disable the date
injection. See [research.md](research.md).

## Solution

A plugin written into `.opencode/plugins/` replaces the `Today's date:` line
with a stable line that points at a `current-date` skill. It uses the v1 hook
`experimental.chat.system.transform`, which receives the system prompt as a
mutable `string[]`:

```ts
const DATE_LINE = /^([ \t]*)Today's date:.*$/gm
const STABLE_DATE_LINE = "$1Today's date: not injected (kept out of the prompt so it stays stable); use the `current-date` skill when you need it."

export const KdnStableSystemPrompt: Plugin = async () => {
  return {
    "experimental.chat.system.transform": async (_input, output) => {
      if (!output || !Array.isArray(output.system)) return
      output.system = output.system.map((part) =>
        typeof part === "string" ? part.replace(DATE_LINE, STABLE_DATE_LINE) : part,
      )
    },
  }
}
```

The skill `.opencode/skills/current-date/SKILL.md` tells the model to run `date`
when it needs the current date. OpenCode injects only the skill's name and
description into the system prompt (stable and sorted); the body loads on demand
through the `skill` tool.

The plugin is guarded: a missing, renamed or differently-shaped hook never
throws, so a request is never broken.

**The plugin is generated; the skill is tracked repo content.** The aspect
generates the plugin as a `/nix/store` symlink, so it cannot be committed. The
skill is opencode-specific, so it lives in `.opencode/` (not `.agents/skills/`)
and is committed as a real file. `.gitignore` re-includes
`.opencode/skills/*/SKILL.md` while the rest of `.opencode/` stays ignored.

The generator lives in both OpenCode trees, so they stay in parity:

- `modules/den/aspects/opencode.nix` — the aspect. `stablePromptPlugin` and the
  `files` entry for the plugin.
- `modules/slots/opencode/default.nix` — the slot, the same.

The system prompt is now byte-identical for the life of a conversation.

## Verification steps

1. Both files parse:

   ```
   nix-instantiate --parse modules/den/aspects/opencode.nix
   nix-instantiate --parse modules/slots/opencode/default.nix
   ```

2. The module evaluates and produces the plugin:

   ```
   res.config.files  ->  [ ".opencode/plugins/kdn-opencode-stable-prompt.ts" ]
   ```

3. The generated plugin text runs correctly under Node:

   ```
   stable across days: true
   mentions skill: true
   guard ok
   ```

4. The skill is tracked, the rest of `.opencode/` is not:

   ```
   git status --porcelain --untracked-files=all .opencode/
   ?? .opencode/skills/current-date/SKILL.md
   git check-ignore .opencode/plugins/kdn-opencode-stable-prompt.ts   # ignored
   ```

5. Entering the shell regenerates the plugin symlink and leaves the tracked
   skill file untouched:

   ```
   devenv shell -- true
   test -L .opencode/skills/current-date/SKILL.md && echo symlink || echo "real file"
   ```

## Follow-up notes

- **Restart OpenCode** to load the plugin and the skill. A running instance
  keeps the old prompt until it reloads.
- The hook is `experimental` and v1-only. OpenCode v2 replaces it with
  `ctx.session.hook("context", ...)`. Revisit the plugin on a v2 upgrade.
- The date is no longer injected, so the model must run `date` (the skill) to
  answer a date question. The alternative is to freeze the first-seen date per
  session id instead of pointing at the skill.
- The instruction content (`AGENTS.md`) is re-read on every request, so editing
  it mid-session still moves the prefix. See
  [prompt-volatility.research.md](prompt-volatility.research.md).

## Correction (2026-10-14) — the first plugin never took effect

The first plugin reassigned the array instead of mutating it:

```ts
output.system = output.system.map((part) => part.replace(DATE_LINE, STABLE_DATE_LINE))
```

OpenCode ignores the hook's return value. `LLMRequestPrep.prepare` builds its own
`system` array, passes `{ system }` to the trigger, and keeps using that same
array afterwards. Reassigning `output.system` to a new array is therefore
silently lost; only an in-place mutation reaches the request. The date was never
stripped, so the midnight rollover and the full re-prefill continued.

Proved with a mock upstream: with the `.map` reassignment the system message
still contained `Today's date: ...`; with `output.system[i] = ...` it contained
the stable line. The original "runs correctly under Node" check called the hook
in isolation and inspected `output.system` itself, so it did not catch this.

The fix mutates the array in place:

```ts
for (let i = 0; i < output.system.length; i++) {
  if (typeof output.system[i] === "string") {
    output.system[i] = output.system[i].replace(DATE_LINE, STABLE_DATE_LINE)
  }
}
```
