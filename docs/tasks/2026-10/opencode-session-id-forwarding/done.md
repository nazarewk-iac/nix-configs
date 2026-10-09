---
type: Solution
description: Fix the plugin to read input.model.providerID and make the compat-proxy forward client headers on the streaming path, so x-session-id reaches llama-server.
task: definition.md
authored_by: agent
timestamp: 2026-10-10T11:00:00+02:00
---

# Forward x-session-id end to end

## Root cause analysis

Two defects stopped the session id from reaching llama-server; see
[research.md](research.md). In short:

1. The generated OpenCode plugin read `input.provider.info.id`, which is
   `undefined`, so the `chat.headers` hook threw. The provider id is
   `input.model.providerID`.
2. The compat-proxy's streaming path forwarded only `Authorization`, so
   `x-session-id` was dropped (OpenCode streams).

## Solution

- `modules/den/aspects/llm-client.nix` and
  `modules/slots/llm/client/default.nix`: the plugin uses
  `input.model.providerID`.
- `nazarewk-iac/opencode_compat_proxy` `proxy.py`
  (`stream_with_sections`): copy the caller's application headers onto the
  upstream request; force `accept`/`content-type`; skip `content-length`,
  `host`, `x-forwarded-for` and (unless `FORWARD_AUTHORIZATION`) `authorization`.
  README feature list updated. Committed `95b85c6`, pushed to the fork `main`.
- `flake.lock`: bumped `opencode-compat-proxy` to `95b85c6`.

## Verification steps

Plugin, scratch project + mock server:

```
$ opencode run --model mock/m 'say hi'
$ cat headers.log
providerID="mock" sid=ses_edb42f27effeA2Z7O6bwOL3xdK
X-SESSION-ID=ses_edb42f27effeA2Z7O6bwOL3xdK
```

Server side, direct (proves the endpoint accepts the id):

```
$ curl ... -H 'x-session-id: probesess1' ... /v1/chat/completions
$ curl ... /slots | jq '.[]|select(.session_id!="")'
{"id":1,"session_id":"probesess1"}
```

Plugin load in this repo:

```
$ opencode debug info
plugins:
- file:///home/kdn/.../nix-configs/.opencode/plugins/kdn-llm-session-id.ts
```

End-to-end (after deploy): a turn from the `ee324` pane makes `GET /slots`
report the `ses_ee324...` id and writes a `llama-session-*.bin`.

## Follow-up notes

- The proxy's non-streaming path already forwarded all headers; only the
  streaming path changed.
- Any other client header a future feature needs (for example a per-agent id)
  now survives the streaming path too.
