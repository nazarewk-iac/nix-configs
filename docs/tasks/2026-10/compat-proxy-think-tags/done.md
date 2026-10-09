---
type: Solution
description: Emit llama-server reasoning in its own reasoning_content delta instead of merging it into content with literal think tags.
task: definition.md
authored_by: agent
timestamp: 2026-10-09T12:40:31+02:00
---

# Solution — keep reasoning_content separate in the compat-proxy

## Root cause analysis

The brys request path is OpenCode → Caddy → `opencode-compat-proxy`
(`kdn-llm-proxy-lan`) → llama-server. llama-server runs with the default
reasoning format `deepseek`, so it streams thinking as `delta.reasoning_content`,
separate from `delta.content`.

The proxy's `stream_with_sections` read `delta.reasoning_content` and re-emitted
it as `delta.content`, wrapping it in literal `&lt;think&gt;` / `&lt;/think&gt;`
tags (`proxy.py` lines 709-720 and 774-776). `_make_content_sse` only ever set
`content`, so the proxy never emitted a `reasoning_content` field. OpenCode's
`@ai-sdk/openai-compatible` adapter parses `delta.reasoning_content`, so it had
nothing to parse and showed the tags as ordinary text. `tokens_reasoning` stayed
zero.

The tag wrapping came from upstream (`ladiossoop5star/opencode_compat_proxy`);
the nazarewk-iac fork inherited it. See [research.md](research.md).

## Solution

Rewrote the streaming emission in the fork
(`nazarewk-iac/opencode_compat_proxy`, commit `fb4f861`) so reasoning and
content stay in their own fields:

- Added `_make_reasoning_sse`, which emits `delta.reasoning_content`.
- Replaced the plain-string `unflushed_text` / `pending` buffers with ordered
  `(kind, text)` segments, where `kind` is `"reasoning"` or `"content"`. The
  section flusher now emits each segment with the matching helper.
- Removed the `&lt;think&gt;` / `&lt;/think&gt;` tag injection entirely.
- Kept the combined `buffer` and the DSML/Qwen tool-call detection unchanged, so
  a raw tool call inside either field is still converted.
- Updated the fork `README.md` to describe the pass-through behaviour.

The package `packages/opencode-compat-proxy/default.nix` builds the fork
unchanged; `flake.lock` was updated to the new fork rev
`fb4f861576433f1863a458d8f39dc53fe80a754a`.

## Verification steps

1. Standalone test (`/tmp/opencode/test_reasoning_proxy.py` + `reasoning_mock.py`)
   against both the working-tree `proxy.py` and the built package:

   ```
   reasoning: reasoning="Let me think. The answer is 42." content="Hello world." usage=true done=true
   dsml:      tool_calls=true dsml_leak=false usage=true done=true
   mixed:     reasoning preserved, tool_calls=true usage=true
   ALL OK
   ```

2. Package build:

   ```
   nix build .#opencode-compat-proxy
   → /nix/store/kywz261ld5496b6z5k5m6s8arsnp85mq-opencode-compat-proxy-unstable-2026-10-08
   ```

3. brys build (no activation): main toplevel `f58hy9a3…`; the
   `llms-frontier` specialisation `ydfjspdi…` carries the fixed proxy.

4. In-place activation on brys (booted into `llms-frontier`): copied the new
   specialisation closure and ran its `switch-to-configuration switch`.
   `/run/current-system` is now `ydfjspdi…`; `kdn-llm-proxy-lan` is active with
   `ExecStart=…/kywz261l…`.

5. Live stream check through the LAN endpoint:

   ```
   curl -skN https://brys.priv.nb.net.int.kdn.im/v1/chat/completions … -d '{"model":"qwen3.8-flash-next","stream":true,"chat_template_kwargs":{"enable_thinking":true,…}}'
   → data: {…"delta": {"reasoning_content": "The user wants me to reply with ", …}}
   ```

   Reasoning now arrives in `reasoning_content`, with no `&lt;think&gt;` tags.

## Follow-up notes

- The switch reported `Failed to reload caddy.service` with
  `open /llm-key: no such file or directory`. This is pre-existing and
  unrelated: Caddy's config reads the TLS key from a systemd credential, which
  the `caddy reload` control process does not receive. The running Caddy kept
  serving the previous config, so the endpoint stayed up; a cold boot starts
  Caddy with the credential present. Worth a separate task if reloads should
  work.
- `switch-to-configuration` also warned about `/etc/subuid` and `/etc/subgid`
  (pre-existing, harmless on this host).
- The raw angle-bracket tags in this task's docs are written as `&lt;…&gt;`
  entities because the agent harness strips literal tags from tool input.

## Follow-up (2026-10-09) — sibling Thought blocks

The first fix exposed a second proxy bug. Each emitted delta carried
`"tool_calls": []`. OpenCode 1.18.29's `@ai-sdk/openai-compatible` adapter closes
the active reasoning block on any non-null `delta.tool_calls`, even an empty
array. Every 32-char section therefore ended its own reasoning block, and the TUI
showed one "Thought" block per chunk.

Fix (fork commit `53aec40`): drop the `tool_calls` field from the emitted
`content` and `reasoning_content` deltas.

The standalone test now folds the stream with the adapter's own rule and asserts
one reasoning block. It passes on the fixed tree and the new package, and fails
on the previous package with three blocks. Package `w487g7vh…`; brys main
toplevel `z3ql1hh9…`; `llms-frontier` `fdcpp0ii…` and `llm-qwen` `06qyyn5b…`
carry the fix. **Not activated** — left for the maintainer.

