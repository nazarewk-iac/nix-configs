---
type: Rule
description: Requires a change to a vendored Pi extension to follow the fork-and-vendor convention.
timestamp: 2026-11-03T13:50:00+01:00
---

# Forking a Pi extension

Full doc: [docs/pi-extension-forks.md](../../docs/pi-extension-forks.md)

When a vendored Pi extension must change and upstream does not have the change:

- Fork into `nazarewk-iac` and branch **from the vendored revision**, not from `main`.
- Keep the fork's `main` identical to upstream. Never commit to it.
- One small, upstreamable patch commit. Prefer a config switch over a hard-coded behaviour.
- Run the fork's `tsc --noEmit` and tests before you push.
- Vendor by pinned `rev` and `hash` with a `+nazarewk.N` suffix; bump all three together.
- Build locally (`--option builders ""`) when the remote builder rejects an unsigned output, then
  confirm Pi loads with no `Failed to load extension`.
- Sync the copies: `checks/pi-harness/extensions/` and `~/.pi/agent/agents/` (a copy, not a link).
- A colon in an unquoted frontmatter value is invalid YAML and breaks the load. Quote it.
