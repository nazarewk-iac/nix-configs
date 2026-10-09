---
type: Task
description: brys model streams show literal &lt;think&gt; tags in OpenCode because the compat-proxy merges reasoning_content into content.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-09T10:40:31+02:00
---

# brys streams show literal think tags

> ✅ **Done** — see the solution in [done.md](done.md).

## Context

OpenCode sessions against **brys** (self-hosted Qwen3.8-Flash-Next and DeepSeek
V4 Flash) show the thinking text as ordinary assistant text, wrapped in the
literal `&lt;think&gt;` and `&lt;/think&gt;` tags. Sessions against **requesty**
show the same thinking in a separate, parsed reasoning part.

Example session: `ses_ee324b411ffe1JJtR5p4wl7I6Z` (model
`brys/qwen3.8-flash-next`, variant `high`). Its text parts start with
`{"type":"text","text":"&lt;think&gt;\n…` and end with `\n&lt;/think&gt;\n`.
Every `step-finish` part records `reasoning: 0`.

## Root cause

The request path on brys is:

```
OpenCode ──HTTPS──▶ Caddy ──▶ opencode-compat-proxy (kdn-llm-proxy-lan) ──▶ llama-server router
```

1. The Qwen model runs with `--reasoning auto` and the **default** llama.cpp
   reasoning format `deepseek` (`common/common.h`:
   `reasoning_format = COMMON_REASONING_FORMAT_DEEPSEEK`). In this format
   llama-server streams the thinking as `delta.reasoning_content`, separate from
   `delta.content` (`tools/server/server-chat.cpp`,
   `server_chat_msg_diff_to_json_oaicompat`).
2. The compat-proxy reads `delta.reasoning_content`, then **rewrites it into
   `delta.content`**, wrapped in the literal `&lt;think&gt;` / `&lt;/think&gt;`
   tags (`proxy.py` lines 709-720 and 774-776). Its `_make_content_sse` helper
   emits only `content` and `tool_calls` — it never emits a `reasoning_content`
   field.
3. OpenCode's `@ai-sdk/openai-compatible` adapter does read
   `delta.reasoning_content` (confirmed in the opencode 1.18.29 binary). It has
   nothing to read, so the tags become visible text and `tokens_reasoning` stays
   zero.

The tag wrapping is **upstream** proxy behaviour
(`ladiossoop5star/opencode_compat_proxy`, `proxy.py`); the nazarewk-iac fork
inherits it and adds only model routing, Authorization forwarding and the
streaming usage chunk. So the fix belongs in the proxy, not in OpenCode.

## Goal

Pass reasoning through unchanged: emit `delta.reasoning_content` for thinking
and `delta.content` for the answer. Do not inject `&lt;think&gt;` /
`&lt;/think&gt;` tags.

## Acceptance criteria

- A streaming brys response keeps thinking in `reasoning_content` and the answer
  in `content`.
- OpenCode shows a separate reasoning part and a non-zero reasoning token count.
- DSML / Qwen tool calls that appear inside the thinking are still detected.
- The packaged `opencode-compat-proxy` builds and keeps the existing usage-chunk,
  routing and auth behaviour.

## References

- [research.md](research.md) — the evidence and the exact code paths.
- [docs/local-llms.md](../../../docs/local-llms.md) — the brys serving topology
  and the compat-proxy.
- [packages/opencode-compat-proxy/](../../../../packages/opencode-compat-proxy/) —
  the package and the pinned fork source.
- [modules/slots/llm/proxy/README.md](../../../../modules/slots/llm/proxy/README.md) —
  the proxy slot.
- [../opencode-self-hosted-token-stats/definition.md](../opencode-self-hosted-token-stats/definition.md) —
  the earlier proxy stream bug (usage chunk).
