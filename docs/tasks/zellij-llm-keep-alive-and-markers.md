---
type: Task
description: Keep a zellij-llm background session alive after its command exits, and detect completion with a deterministic file marker.
status: done
authored_by: agent
timestamp: 2026-07-31T18:30:00+02:00
---

# Keep zellij-llm sessions alive; use file markers

## Problem

A background `zellij-llm` session went EXITED once the fed command finished. The user could not
attach to review the previous output. A zellij session dies when all its panes' processes end.
The command pane held the only process, so the session ended with it.

The prior exit detection read the `list-panes` exited flag. A persisted pane never reports
exited, so that signal no longer works under a keep-alive pane.

## Goal

- After the command exits, the pane drops to the default user shell. It does not stay at the
  "exited" message and does not close. A live shell holds the session up.
- `--ephemeral` keeps the old behavior: the pane closes on exit and is not reviewable (rare
  case).
- Detect completion with a deterministic file marker under a known cache path, not from the
  `list-panes` flag and not from stdout sentinels.

See the solution in [[zellij-llm-keep-alive-and-markers.done]].
