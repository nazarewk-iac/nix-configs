---
type: Research
description: Proof that the fleet-status tool returns live loaded-alias and headroom state, and degrades to a static `stale: true` view when brys is unreachable.
task: definition.md
authored_by: agent
timestamp: 2026-11-02T11:35:00+01:00
---

# Proof: fleet-status returns live state, and degrades when brys is down

Part 3 of the task. The orchestrator cannot see the fleet, so it cannot know whether a switch costs
a cold load or whether the host has headroom. This one read-only tool answers both. It reads two
endpoints and, by design, never throws: a network fault returns the static view with `stale: true`
(review caveat C5).

## Why `/v1/models` and not `/running`

`/v1/models` already publishes the loaded state per alias in `status.value` (`loaded` | `unloaded`),
together with `context_length`. So loaded-ness **and** context come from ONE call. The research file
assumed `/running` was needed and that its base ids then needed a join against the alias map — the
review's A2 finding. `/v1/models` removes that join. `/metrics` supplies the host headroom, which
the review (R1) confirmed is host-scoped.

## The live run

The tool's pure logic is exercised against the real fleet; the command below is the same code path
the extension runs inside a session, with the base URL injectable so both paths can be shown without
a live Pi session.

```bash
KDN_LLM_BASE_URL=https://brys.priv.nb.net.int.kdn.im node flux-standalone.mjs
```

Live output, verbatim from one capture:

```json
{
  "stale": false,
  "loaded": [
    "chat-deep-slow",
    "code-deep-slow",
    "orchestrate-deep-slow",
    "qwen",
    "qwen3.8-27b",
    "qwen3.8-flash-next",
    "reason-deep-slow",
    "tools-deep-slow",
    "vision-deep-slow"
  ],
  "resources": {
    "ram_used_gb": 26.5,
    "ram_total_gb": 125.7,
    "swap_used_gb": 15.3,
    "swap_total_gb": 62.8,
    "vram_used_gb": 7,
    "vram_total_gb": 12,
    "load1": 0.1
  },
  "modelCount": 81
}
```

The `loaded` set matches the fleet joined through the alias map; `resources` matches `/metrics`
(`llamaswap_memory_total_bytes` = 125.7 GiB, the host total).

## The degradation run (brys unreachable)

Same logic, pointed at a dead address:

```bash
KDN_LLM_BASE_URL=https://127.0.0.1:1 node flux-standalone.mjs
```

```json
{ "stale": true, "loaded": [], "resources": null, "modelCount": 0 }
```

No exception, no hang past the 3 s timeout budget: the tool answers that the state is unknown
rather than blocking a delegation. The `note` field in the real tool says "fleet unreachable; static
view only. Do not assume anything is loaded."

## Reaching the engaged parent (a required, non-obvious step)

The tool is only useful if the orchestrator can call it. In engaged mode pi-orchestrator keeps
**only** `delegate` plus the names in its `keepTools` list; a plain `--tools` flag is overridden.
Verified by capturing the outbound request body:

```
# default engaged parent:            TOOLS_SENT: ["delegate"]
# with orchestrator.jsonc keepTools: TOOLS_SENT: ["delegate", "measure", "fleet-status"]
```

So `devenv.nix` renders `.pi/extensions/orchestrator.jsonc` (git-ignored, generated) with:

```json
{ "keepTools": ["delegate", "measure", "fleet-status"] }
```

The file is read from `cwd/.pi/extensions/` first, so it travels with the checkout.

## What this proves, and what it does not

**Proves:** the tool returns real loaded-alias and headroom values on this host; it degrades to a
static empty view with `stale: true` when brys is unreachable; both `measure` and `fleet-status`
reach the engaged orchestrator when `keepTools` names them.

**Does not prove:** that the orchestrator will always call the tool before choosing. Like the context
gate, this is advisory data plus a prompt rule; the unskippable check is the context gate on
`delegate` (Part 1). The proof is at the code and schema level.
