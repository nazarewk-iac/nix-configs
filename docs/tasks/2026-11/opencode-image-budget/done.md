---
type: Solution
description: A generated OpenCode plugin that prunes outgoing images to a budget, gives compaction a zero image budget, and learns an unknown gateway cap from the rejection.
task: definition.md
authored_by: agent
timestamp: 2026-11-20T12:00:00+01:00
---

# Solution

## What changed

| Path | Change |
| --- | --- |
| `modules/den/aspects/opencode/kdn-image-budget.ts` | New. The plugin source: 300 lines, no dependency. |
| `modules/den/aspects/opencode.nix` | Generates `.opencode/plugins/kdn-image-budget.ts`, injects `kdn.opencode.imageBudget`, extends `enterTest`. |
| `docs/opencode-image-budget.md` | New. The operator view: what it does, the options, how to recover a session that is already over the cap. |

## How it works

The plugin registers four request hooks and one retry hook:

| Hook | Budget | Why |
| --- | --- | --- |
| `context` | the configured budget | The agent loop. This is the request that bricks. |
| `generate` | the configured budget | Transient generation from the session context. |
| `compaction` | 0 images | A summary does not need pixels, and a compaction carrying every image fails the same way. |
| `title` | 0 images | Same, and the title model needs no image. |
| `retry` | — | Learns the cap from `Too many images in request: N > M`, stores it, forces one retry. |

The plugin walks `messages` for image parts. OpenCode 2.2.5 hands the hook provider-shaped messages
(`{ role, content }` with `text` / `reasoning` / `tool-call` / `tool-result` parts), where a tool
result nests its content in `result.value`. The domain shape (`assistant.content[].state.content[]`,
`user.files[]`) is handled too, so a future release that changes the shape keeps working.

Each pruned image becomes one line in the position it held:

```
[image omitted from this request by the image budget: /tmp/opencode/kvm/anji4.jpg (image/jpeg, 90 KiB). Read the file again to look at it.]
```

## Options

`kdn.opencode.imageBudget`: `maxImages` (8), `maxBytes` (`8MiB`), `compaction.{maxImages,maxBytes}`
(0), `providers.<id>`, `models."<provider>/<model>"`, `debug`.

## Verification

59 unit checks plus four live checks against the bricked session and a fork of it. See
`definition.md` § Verification.
