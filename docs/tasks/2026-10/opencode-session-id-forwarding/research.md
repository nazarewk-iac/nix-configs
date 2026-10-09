---
type: Research
description: Diagnosis of why x-session-id never reaches llama-server — the plugin's undefined field and the compat-proxy streaming header allowlist.
task: definition.md
authored_by: agent
timestamp: 2026-10-10T10:30:00+02:00
---

# Diagnosis: x-session-id does not reach llama-server

## Symptom

On brys, every busy Qwen slot reported `session_id: ""`, and a long session
(`ee324`) re-prefilled ~60K tokens on every turn (19-27 tok/s for tens of
minutes). The disk session store stayed empty.

## Defect 1 — the plugin read the wrong field

The generated plugin (`.opencode/plugins/kdn-llm-session-id.ts`) used:

```js
if (PROVIDERS.has(input.provider.info.id)) { ... }
```

`input.provider` is the provider **context** object (source/info/options); it
has no `.info.id`. OpenCode aborts the hook with
`undefined is not an object (evaluating 'input.provider.info.id')`.

The `chat.headers` hook input carries the provider id at
`input.model.providerID`. OpenCode's own built-in plugins do the same:

```
"chat.headers": async (input, output) => {
  if (!input.model.providerID.includes("github-copilot")) return
  ...
}
```

`opencode debug info` confirmed the plugin loads
(`file:///.../.opencode/plugins/kdn-llm-session-id.ts`).

A scratch-project mock-server test proved the fix: with
`input.model.providerID`, the hook fired and the server received
`X-SESSION-ID=ses_...`. With `input.provider.info.id`, the request failed.

## Defect 2 — the compat-proxy drops the header on the streaming path

The client path is OpenCode -> Caddy -> compat-proxy (`:9530`) ->
llama-server (`:39703`). The non-streaming path forwards every client header
(`proxy.py`, `upstream_headers = strip_hop_by_hop_headers(dict(request.headers))`),
but the **streaming** path built a fresh set:

```python
req_headers = {"Accept": "text/event-stream"}
if upstream_headers and FORWARD_AUTHORIZATION:
    for k, v in upstream_headers.items():
        if k.lower() == "authorization":
            req_headers["Authorization"] = v
```

OpenCode streams, so `x-session-id` was dropped. Direct proof: a request to the
router with header `x-session-id: probesess1` made `GET /slots` report
`session_id: "probesess1"`; the same header through the proxy never appeared.

## Fix

- Plugin: read `input.model.providerID` (both the den aspect and the slot).
- Proxy: on the streaming path, copy the caller's application headers and force
  only `accept`/`content-type`, skipping `content-length`/`host`/
  `x-forwarded-for` (set by the proxy) and `authorization` unless
  `FORWARD_AUTHORIZATION` is on.

The proxy is a `flake = false` input; the fix is on the `nazarewk-iac/...`
fork `main` and the lock was bumped.
