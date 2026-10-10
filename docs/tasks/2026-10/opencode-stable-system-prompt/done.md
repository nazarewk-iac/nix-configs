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

A plugin written into `.opencode/plugins/` removes the `Today's date:` line. It
uses the v1 hook `experimental.chat.system.transform`, which receives the system
prompt as a mutable `string[]`:

```ts
const DATE_LINE = /^[ \t]*Today's date:.*\n?/gm

export const KdnStableSystemPrompt: Plugin = async () => {
  return {
    "experimental.chat.system.transform": async (_input, output) => {
      if (!output || !Array.isArray(output.system)) return
      output.system = output.system.map((part) =>
        typeof part === "string" ? part.replace(DATE_LINE, "") : part,
      )
    },
  }
}
```

The plugin is guarded: a missing, renamed or differently-shaped hook never
throws, so a request is never broken.

The generator lives in both OpenCode trees, so they stay in parity:

- `modules/den/aspects/opencode.nix` — the aspect. `stablePromptPlugin` plus
  `files.".opencode/plugins/kdn-opencode-stable-prompt.ts".text`.
- `modules/slots/opencode/default.nix` — the slot, the same string and `files`
  entry.

The date is removed, not frozen. The system prompt is now byte-identical for the
life of a conversation.

## Verification steps

1. Both files parse:

   ```
   nix-instantiate --parse modules/den/aspects/opencode.nix
   nix-instantiate --parse modules/slots/opencode/default.nix
   ```

2. The module evaluates and produces the file:

   ```
   res.config.files  ->  [ ".opencode/plugins/kdn-opencode-stable-prompt.ts" ]
   ```

3. The generated plugin text runs correctly under Node:

   ```
   date removed: true
   stable across days: true
   guard ok
   ```

4. Entering the shell materializes the file:

   ```
   devenv shell -- true
   ls -la .opencode/plugins/
   kdn-opencode-stable-prompt.ts -> /nix/store/...-opencode-plugins-kdn-opencode-stable-prompt.ts
   ```

## Follow-up notes

- **Restart OpenCode** to load the plugin. A running instance keeps the old
  prompt until it reloads its plugins.
- The hook is `experimental` and v1-only. OpenCode v2 replaces it with
  `ctx.session.hook("context", ...)`. Revisit the plugin on a v2 upgrade.
- The date is no longer available to the model. If that matters, the alternative
  is to freeze the first-seen date per session id instead of removing it.
