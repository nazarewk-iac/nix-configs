---
type: Task
description: OpenCode shows zero token usage for every self-hosted brys model because the compat-proxy drops the streaming usage chunk.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-08T23:42:07+02:00
---

# Self-hosted token stats: the compat-proxy drops the streaming usage chunk

> ✅ **Done** — see the solution in [done.md](done.md).

## Context

OpenCode shows no token statistics for any model served from **brys** (the
self-hosted llama.cpp router behind the `opencode-compat-proxy`). The token
counter stays at zero for text and for tool-call responses. Requesty-served
models (for example DeepSeek V4.1 Flash) show normal counts.

The initial report framed this as an OpenCode configuration problem and proposed
adding `includeUsage: true` to the provider block. That is a red herring:
OpenCode 1.18.29 already forces `includeUsage = true` for every
`@ai-sdk/openai-compatible` provider unless it is explicitly set to `false`.

## Evidence (session database)

The OpenCode session database (`~/.local/share/opencode/opencode-stable.db`)
records the split directly. Every session whose `model` is `brys` has zero
tokens; every `requesty` session has real counts.

| provider | example model | `tokens_input` / `tokens_output` |
|---|---|---|
| `requesty` | `deepseek-v4.1-flash` | e.g. `164041 / 18371` |
| `brys` | `deepseek-v4-flash` | `0 / 0` |

The same zero appears in each assistant `message.data.tokens` and each
`step-finish` part. Tool calls themselves worked (they were translated by the
proxy and completed), so only the usage accounting was missing.

## Root cause

The request path on brys is:

```
OpenCode ──HTTPS──▶ Caddy ──▶ opencode-compat-proxy (:9530) ──▶ llama-server router
```

1. OpenCode sends `stream_options.include_usage: true` (forced by its AI SDK
   adapter).
2. The proxy forwards the body unchanged, so llama.cpp v0.6.0 **does** emit the
   OpenAI usage chunk — an SSE chunk with an **empty `choices` array** and a
   `usage` (plus `timings`) object (`tools/server/server-schema.cpp:26`,
   `tools/server/server-task.cpp:502`).
3. The proxy's `stream_with_sections` discarded that chunk:

   ```python
   choices = ev.get("choices", [])
   if not choices:
       continue          # <-- the usage chunk has empty choices; dropped here
   ```

4. The DSML tool-call path returned early as soon as it parsed a tool block, so
   it never reached the usage chunk either (and it also skipped the `[DONE]`
   terminator).

So the server produced the data and OpenCode asked for it; the proxy in the
middle threw it away.

## Goal

Preserve the upstream usage chunk through the proxy on **both** streaming paths
(plain text and DSML tool calls), so OpenCode can display token statistics.

## Acceptance criteria

- A streaming text response through the proxy carries `usage`.
- A streaming DSML tool-call response through the proxy carries `usage` and a
  `[DONE]` terminator.
- No DSML markup leaks into the client stream.
- The packaged `opencode-compat-proxy` builds and shows the same behaviour.

## References

- [docs/local-llms.md](../../../docs/local-llms.md) — the brys serving topology
  and the compat-proxy.
- [packages/opencode-compat-proxy/](../../../../packages/opencode-compat-proxy/) —
  the package, its patches, and the pinned upstream source.
- [modules/slots/llm/proxy/README.md](../../../../modules/slots/llm/proxy/README.md) —
  the proxy slot.
