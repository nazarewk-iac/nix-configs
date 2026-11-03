---
type: Task
description: Settle the Pi harness on one delegation extension and port the missing orchestrator tools (measure, fleet-status, slice) into the pi-orchestrator fork.
status: open
authored_by: agent
timestamp: 2026-11-03T20:10:00+01:00
---

# Consolidate the Pi harness on the orchestrator fork

## Context

Two delegation paths existed at once. `pi-orchestrator` provides `delegate` and an engaged mode;
our own `subagent` extension provided a rival `subagent` tool. Both read the same agent directory
(`~/.pi/agent/agents/*.md`) with different frontmatter dialects — ours honoured `isolated` and
`context: full`, the orchestrator honours `tools`/`blockTools`/`model`/`thinking`/`maxTurns`/`hidden`
and its own `childContext` policy. A file could therefore mean two different things depending on
which extension loaded it.

Done in this task, step 1: the `subagent` extension is deleted, `isolated:` keys are inert (the
orchestrator ignores them), and `delegate` is the only way a child is spawned. `docs/pi-harness.md`
records the inventory and the rule: a missing orchestrator feature goes into the fork, not a second
extension.

## Remaining work

The orchestrator fork (`nazarewk-iac/child-context`) is the place for the three features that today
live beside it or were dropped with `subagent`. Each is a small, self-contained patch on the fork,
so a later upstream bump is a rebase.

1. **Port `measure`** from `packages/pi-coding-agent-extensions/orchestrator-gate/`. It sizes a file
   or a byte count against a model alias' served context and degrades to allow on a network fault.
   Its own header says it is separate only because pi-orchestrator is vendored at a pinned commit;
   the fork removes that reason.
2. **Port `fleet-status`** from `packages/pi-coding-agent-extensions/fleet-status/`. It reports the
   loaded aliases, their served context and the host headroom. Its natural home is the extension
   that already renders the fleet panel from `RunningTask` state.
3. **Port `slice`** (dropped with `subagent`). `planSlices`/`sliceTask` split ONE oversized artifact
   into bounded line ranges that each fit a child's window, then run one child per range. This is a
   real `delegate` gap: a child cannot split a file it cannot read without overflowing first.
   Keep `slice.ts` and `slice.test.ts` as the reference (they were deleted with the extension;
   recover them from the commit that removed them).

After each port: delete the local directory, bump the fork `rev`+`hash`, and confirm
`delegate`'s `--exclude-tools`/tool-allowlist logic still exposes the new tool while engaged
(`keepTools` in `orchestrator.jsonc`).

## Acceptance

- `packages/pi-coding-agent-extensions/` contains no extension that spawns a child or sizes a task;
  only `timestamps`, `idle-marker`, `session-digest` and the vendored forks remain.
- `pi-orchestrator` exposes `delegate`, `measure`, `fleet-status` and `slice` from one source.
- `docs/pi-harness.md` inventory lists no `interim` rows.

## Related

- [docs/pi-harness.md](../../../pi-harness.md) — inventory, policy, caveats.
- [docs/pi-extension-forks.md](../../../pi-extension-forks.md) — fork, patch and vendor by pinned rev.
