---
type: Task
description: Stop OpenCode from injecting the current date into the system prompt, so the prompt prefix is stable and a local llama-server reuses its KV cache across midnight instead of re-prefilling the whole conversation.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-12T07:07:10+02:00
---

# Stable OpenCode system prompt (no date injection)

> ✅ **Done** — see the solution in [done.md](done.md).

## Context

OpenCode builds the system prompt with an `<env>` block that ends in
`Today's date: <date>` (`packages/opencode/src/session/system.ts:81`, version
1.18.29). The date changes at midnight, so the prompt prefix changes and a
server-side prompt cache cannot reuse it.

On the hybrid Qwen model on brys this is expensive: a divergence inside the
system prompt is before the first context checkpoint, so llama.cpp forces a full
re-process of the whole conversation (see
[../llm-warm-start-session/hybrid-reuse.research.md](../llm-warm-start-session/hybrid-reuse.research.md)).
A ~258K-token conversation costs ~2.6 h before the first token.

## Goal

Remove the date line from the system prompt, so the prefix is byte-stable for
the life of a conversation.

## Findings

- OpenCode 1.18.29 has **no config option and no environment variable** to
  disable the date injection. See [research.md](research.md).
- The only supported hook is the plugin `experimental.chat.system.transform`,
  which receives the system prompt as a mutable `string[]`. The date is one line
  in that array.
- The `kdn.opencode` aspect already writes files into `.opencode/`, and the
  `kdn.llm-client` aspect already writes a plugin there, so the mechanism
  exists.

## Approach

1. Write a plugin into `.opencode/plugins/` that removes the `Today's date:`
   line from the system prompt.
2. Own it in the `kdn.opencode` aspect (`modules/den/aspects/opencode.nix`),
   because the date injection is general to OpenCode, not specific to the LAN
   providers. Mirror it in the slot (`modules/slots/opencode/default.nix`).
3. Guard the hook so a missing or renamed hook never breaks a request.

## Acceptance criteria

- The generated `.opencode/plugins/kdn-opencode-stable-prompt.ts` exists.
- With the plugin loaded, the system prompt has no `Today's date:` line.
- Two requests on different days produce an identical system prompt.

## Open questions

- The hook is `experimental` and v1-only. OpenCode v2 replaces it with
  `ctx.session.hook("context", ...)`. The plugin must be revisited on a v2
  upgrade.
- The date is removed, not frozen. A model cannot answer a date question from
  the prompt. The alternative (freeze the first-seen date per session) keeps the
  date but needs per-session state in the plugin.

## References

- [research.md](research.md) — the injection site and the hook.
- [../llm-warm-start-session/hybrid-reuse.research.md](../llm-warm-start-session/hybrid-reuse.research.md)
  — why an early prompt change forces a full re-prefill.
