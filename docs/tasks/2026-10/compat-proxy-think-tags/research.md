---
type: Research
description: Evidence that the compat-proxy merges llama-server reasoning_content into content with literal think tags, so OpenCode cannot parse it.
task: definition.md
authored_by: agent
timestamp: 2026-10-09T10:40:31+02:00
---

# Research — why brys streams carry literal think tags

## Observation

OpenCode stores the thinking text of a brys model as a `text` part, not a
`reasoning` part. Session `ses_ee324b411ffe1JJtR5p4wl7I6Z`
(`brys/qwen3.8-flash-next`, variant `high`) has text parts of this shape
(hexdump of `part.data`, id `prt_11fb26ce7001lMHSqbkvwh6Akl`):

```
{"type":"text","text":"&lt;think&gt;\nLet me get back on track…
…\n\n&lt;/think&gt;\n…
```

`sqlite3 … "SELECT … FROM session WHERE id='ses_ee324b411ffe1JJtR5p4wl7I6Z'"` shows
`tokens_reasoning = 0`, and every `step-finish` part shows `"reasoning":0`.

## Database comparison: brys versus requesty

Group the `part` table by the session `model.providerID` and the part `type`,
for rows whose text contains the `think` open tag:

| provider | part type | count |
|---|---|---|
| `brys` | `text` | 10 |
| `requesty` | `reasoning` | 1 |
| `requesty` | `text` | 2 (incidental, not model output) |

So the requesty path delivers a proper `reasoning` part that OpenCode parses;
the brys path delivers a `text` part with visible tags. The difference is the
compat-proxy in the brys path.

## The brys request path

```
OpenCode ──HTTPS──▶ Caddy ──▶ opencode-compat-proxy (kdn-llm-proxy-lan, :9530) ──▶ llama-server (:39703)
```

- The proxy is `kdn.llm.local`'s loopback `kdn-llm-proxy-lan` service
  (`modules/slots/llm/default.nix`, `compatProxy.enable` defaults `true`).
- Caddy fronts it; the proxy forwards to `UPSTREAM_URL = http://127.0.0.1:39703`.
- The client model entry is `@ai-sdk/openai-compatible`
  (`modules/slots/llm/client/default.nix`) with `reasoning = true`
  (`hosts/oams/devenv.nix`, `tierModel`).

## llama.cpp side: reasoning goes to `reasoning_content`

`llama.cpp`'s default reasoning format is `deepseek`:

```c
// common/common.h
enum common_reasoning_format {
    COMMON_REASONING_FORMAT_NONE,
    COMMON_REASONING_FORMAT_AUTO,            // Same as deepseek, using `message.reasoning_content`
    COMMON_REASONING_FORMAT_DEEPSEEK_LEGACY, // … or leave inline in &lt;think&gt; tags in stream mode
    COMMON_REASONING_FORMAT_DEEPSEEK,        // Extract thinking tag contents … including in streaming deltas.
    …
};
common_reasoning_format reasoning_format = COMMON_REASONING_FORMAT_DEEPSEEK;
```

The server only sets `reasoning_in_content` for the legacy format in stream
mode (`tools/server/server-schema.cpp`):

```c
ctx.params.chat_parser_params.reasoning_in_content =
    ctx.params.stream && (reasoning_format == COMMON_REASONING_FORMAT_DEEPSEEK_LEGACY);
```

The stream delta carries the thinking in its own field
(`tools/server/server-chat.cpp`, `server_chat_msg_diff_to_json_oaicompat`):

```c
if (!diff.reasoning_content_delta.empty()) {
    delta["reasoning_content"] = diff.reasoning_content_delta;
}
```

The slot sets `perf.reasoning = "auto"` (`hosts/brys/llm.nix`, `qwenPerf`), which
is `--reasoning auto` (`-rea`). It does **not** set `--reasoning-format`, so the
default `deepseek` applies. Therefore llama-server streams thinking as
`delta.reasoning_content`.

## Proxy side: it merges reasoning into content

`opencode-compat-proxy` (`proxy.py`, the pinned nazarewk-iac fork at
`891cb20c`) reads the reasoning field and re-emits it as content:

```python
# proxy.py:699
reasoning = delta.get("reasoning", "") or delta.get("reasoning_content", "")
text = delta.get("content", "")

is_reason = bool(reasoning)
raw_chunk_text = reasoning if is_reason else text
…
# proxy.py:709-720
chunk_text = ""
if is_reason:
    if thinking_state == 0:
        chunk_text += "&lt;think&gt;\n"
        thinking_state = 1
    chunk_text += raw_chunk_text
else:
    if thinking_state == 1:
        chunk_text += "\n&lt;/think&gt;\n"
        thinking_state = 2
    chunk_text += raw_chunk_text
```

The close tag is also appended at end of stream (`proxy.py:774-776`). Every
emitted chunk goes through `_make_content_sse`, which sets only `content`:

```python
# proxy.py:600-606
def _make_content_sse(chunk_id, model, text):
    return "data: " + json.dumps({
        …
        "choices": [{"index": 0, "delta": {"content": text, "tool_calls": []}}],
    }, ensure_ascii=False) + "\n\n"
```

So the proxy never emits `reasoning_content`. The client only ever sees
`content`.

Note the contradiction: the same proxy sets
`merge_reasoning_content_in_choices = False` on the request
(`proxy.py:529-535`, a Requesty/OpenRouter parameter), i.e. it asks the upstream
to keep reasoning separate — and then merges it into content itself.

## OpenCode side: the adapter would parse `reasoning_content`

OpenCode 1.18.29 bundles `@ai-sdk/openai-compatible`. Its compiled binary
(`.opencode-wrapped`) contains:

```js
// non-stream
let D = W.message.reasoning_content ?? W.message.reasoning;
if (D != null && D.length > 0) N.push({type:"reasoning", text:D});

// stream
let UG = C.reasoning_content ?? C.reasoning;
if (UG) { … W.enqueue({type:"reasoning-start", id:"reasoning…}) … }
```

It also knows the interleaved field for openai-compatible DeepSeek models:
`interleaved: { field: "reasoning_content" }`.

So if the proxy passed `reasoning_content` through, OpenCode would create a
`reasoning` part and count reasoning tokens. The merge into `content` is the
sole reason it does not.

## Attribution: upstream, not the fork

`curl https://raw.githubusercontent.com/ladiossoop5star/opencode_compat_proxy/main/proxy.py`
already contains the `thinking_state` wrapping (`proxy.py` lines 611-621, 663-665
in the 806-line upstream file). The nazarewk-iac fork
(`packages/opencode-compat-proxy/default.nix`, rev `891cb20c`) inherits it and
adds only model routing, Authorization forwarding and the streaming usage chunk.
So a fix must either patch the fork or be sent upstream.

The fork's `README.md` feature list says "Reasoning content — Accumulates
`reasoning`/`reasoning_content` fields and still catches tool calls within them",
and the streaming description says the stream "passes through normally" when no
tool call is found. The code does not do that: it merges reasoning into content
with tags.

## Non-streaming path

`convert_non_streaming_response` (`proxy.py:395-414`) only rewrites `content`
and `tool_calls`; it leaves `message.reasoning_content` in place. So a
**non-streaming** request would carry reasoning correctly. OpenCode always
streams, so only the streaming path matters.

## Fix options

1. **Preferred** — patch the fork's `stream_with_sections` to emit
   `delta.reasoning_content` for reasoning deltas and `delta.content` for answer
   deltas, and drop the tag wrapping. Keep scanning the reasoning text for DSML
   tool calls (the code already buffers both fields together).
2. Add a proxy option (for example `PASSTHROUGH_REASONING=1`) and turn it on for
   the `kdn-llm-proxy-lan` instance.
3. No clean client-side workaround: OpenCode cannot un-merge content. Disabling
   thinking (`enable_thinking=false`) hides the tags but removes thinking.

## Verification (read-only)

- `sqlite3 ~/.local/share/opencode/opencode-stable.db` queries above.
- Hexdump of a stored text part: `sqlite3 … "SELECT hex(substr(data,1,45)) FROM part WHERE id='…'"`.
- Proxy source: `/nix/store/mvljx7098gsis2f1maccs2nk4gszfd8b-source/proxy.py`
  (the locked fork source).
- OpenCode adapter: `grep -a -o '.\{80\}reasoning_content.\{80\}' <opencode>/.opencode-wrapped`.
