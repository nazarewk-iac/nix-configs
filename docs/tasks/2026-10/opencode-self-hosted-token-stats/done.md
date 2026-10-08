---
type: Solution
description: Preserve the empty-choices streaming usage chunk in the compat-proxy (now the nazarewk-iac fork) on both streaming paths.
task: definition.md
authored_by: agent
timestamp: 2026-10-08T23:42:07+02:00
---

# Solution — preserve the streaming usage chunk in the compat-proxy

## Root cause analysis

OpenCode already asks for usage: its AI SDK adapter forces
`includeUsage = true` on every `@ai-sdk/openai-compatible` provider, so the
request carries `stream_options.include_usage: true`. The brys `llama-server`
(v0.6.0, build 11429) supports the flag (`server-schema.cpp:26`,
`server-task.cpp:502`) and emits a final SSE chunk with an **empty `choices`
array** and a `usage` object.

The `opencode-compat-proxy` in front of the router parsed each SSE chunk and
threw that one away:

```python
choices = ev.get("choices", [])
if not choices:
    continue
```

The DSML tool-call branch was worse: it `return`ed as soon as it emitted the
tool-call chunks, so it never read the usage chunk and never sent `[DONE]`.

The session database confirms the effect is specific to the self-hosted path:
every `brys` session stored `tokens_input=0`, while every `requesty` session
stored real counts.

## Solution

The fix lives in the
[`nazarewk-iac/opencode_compat_proxy`](https://github.com/nazarewk-iac/opencode_compat_proxy)
fork, which replaces the in-tree patch series this repo used to carry:

- `main` aggregates three commits on top of upstream `1ae3a3d` — `forward-auth`,
  `router`, and `stream-usage`.
- `forward-auth` and `stream-usage` branch off upstream; `router` stacks on
  `forward-auth` because it depends on the Authorization change.
- This repo consumes the fork as a `flake = false` flake input named
  `opencode-compat-proxy` (`flake.nix`), and
  `packages/opencode-compat-proxy/default.nix` uses it as `src` with no
  `applyPatches`. The former `packages/opencode-compat-proxy/patches/` directory
  is gone.

The `stream-usage` change in `stream_with_sections` (`proxy.py`):

1. **Capture.** When a chunk has empty `choices`, keep it if it carries a
   `usage` object instead of discarding it.
2. **Plain-text path.** Attach `usage` to the synthesized final stop chunk and
   also re-emit the upstream usage chunk before `[DONE]`.
3. **DSML tool-call path.** Replace the early `return` with a
   `tool_calls_emitted` flag and keep draining the upstream stream (suppressing
   trailing content) so the usage chunk is read; then emit the usage chunk and
   `[DONE]`. This also restores the `[DONE]` terminator that the early return
   skipped.

The change preserves the upstream `timings` field too, because the usage chunk is
re-emitted as received (only `id` and `model` are normalized).

## Verification steps

1. The fork's `main` is the aggregate of one commit per patch:

   ```shell
   git -C ~/dev/github.com/nazarewk-iac/opencode_compat_proxy log --oneline main
   # 891cb20 fix: preserve the streaming usage chunk for token stats
   # 09a3f82 feat: route each model to its owning llama-server router
   # 62056f4 fix: forward client Authorization header on the streaming path
   ```

2. Behavioural test against a mock llama-server. The mock emits the usage chunk
   **only** when it receives `stream_options.include_usage`, so the test also
   proves the proxy forwards that field. Two mock modes were exercised: plain
   text and a DSML tool block split across content chunks. Observed summary
   (helper harness kept out of the repo, in `/tmp/opencode`):

   ```
   UNPATCHED text       usage=False tool_calls=False done=True  dsml_leak=False
   UNPATCHED dsml-tool  usage=False tool_calls=True  done=False dsml_leak=False
   PATCHED   text       usage=True  tool_calls=False done=True  dsml_leak=False
   PATCHED   dsml-tool  usage=True  tool_calls=True  done=True  dsml_leak=False
   ```

   The unpatched tool path loses both `usage` and `[DONE]`; the patched path
   keeps both and leaks no DSML.

3. The packaged derivation builds from the fork input and behaves the same:

   ```shell
   nix build .#opencode-compat-proxy --no-link --print-out-paths
   # the built lib/proxy.py equals the fork's main proxy.py
   # then run the built bin/opencode-compat-proxy against the mock:
   BUILT text       usage=True tool_calls=False done=True dsml_leak=False
   BUILT dsml-tool  usage=True tool_calls=True  done=True dsml_leak=False
   ```

4. Live check on the deployed brys endpoint (after the host is rebuilt). Before
   the fix, a streaming request returned no `usage` while the non-streaming
   request did:

   ```shell
   KEY=$(cat /run/configs/llms/llama-server/api-keys/default)
   curl -sS -N -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
     https://brys.priv.nb.net.int.kdn.im/v1/chat/completions \
     -d '{"model":"qwen3.8-flash-next-16k","stream":true,
          "stream_options":{"include_usage":true},
          "messages":[{"role":"user","content":"hi"}]}' | grep usage
   ```

   After the fix this prints a chunk with `"usage"`.

## Follow-up notes

- **Deployment.** The fix lives in the `opencode-compat-proxy` package, which
  brys runs as a systemd service. The running brys system needs a
  rebuild/switch, and OpenCode must be restarted, before the stats appear. This
  task does not perform the deploy.
- **Updating the proxy.** Edit the fork (one branch per change; `main`
  aggregates them), then bump the input:
  `nix flake lock --update-input opencode-compat-proxy`. There are no in-tree
  patches any more.
- **Org token caveat.** The `nazarewk-iac` org rejects the system fine-grained
  PAT that `/etc/nix/nix.access-tokens.auto.conf` provides (`HTTP 403`, token
  lifetime greater than 366 days). The lock was made with the `gh` OAuth token:
  `NIX_CONFIG="access-tokens = github.com=$(gh auth token)" nix flake lock`.
- **Non-streaming path** already carried `usage` and needed no change.
- **`timings`** is forwarded but OpenCode ignores it; it is kept for
  compatibility with other OpenAI-compatible clients.
