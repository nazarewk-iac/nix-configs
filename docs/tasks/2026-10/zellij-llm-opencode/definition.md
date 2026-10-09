---
type: Task
description: Add a `zellij-llm opencode` subcommand set to spawn, drive, and watch OpenCode sessions in dedicated zellij panes, activating devenv when a devenv.nix is present.
status: open
authored_by: agent
timestamp: 2026-10-10T02:00:00+02:00
---

# `zellij-llm opencode`: drive OpenCode sessions in dedicated panes

## Context

`zellij-llm` (`packages/llm/zellij-llm/`) already spawns, watches, and peeks a
command in a dedicated zellij session (its own socket dir, a stacked-pane
layout, a run marker). It has `spawn`, `spawn-and-watch`, `watch`, `wait`,
`peek`, and `list`. It knows nothing about OpenCode.

OpenCode sessions are long-lived TUIs. Driving one today is manual: find the
pane, focus it, type a prompt, press Enter, then watch it. The monitor written
by hand for the `ee324` session on 2026-10-10 (`/tmp/opencode/ee324-monitor.sh`)
does exactly this and should become a first-class feature.

The repository already runs OpenCode inside a `devenv shell` (`kdn.opencode`),
so a spawned OpenCode pane must activate the project's devenv when one exists.

## Goal

A `zellij-llm opencode` command set that:

- `spawn` — start OpenCode in a dedicated pane, in the current project, inside
  its devenv shell when a `devenv.nix`/`devenv.yaml` is present, else plain.
- `send` — write a prompt to a running OpenCode pane and submit it (the
  "continue the work" + Enter of the manual workflow).
- `watch` — follow the session, detect when it goes idle (the turn finished) or
  errors, and report. A bounded `--for <duration>` mode for a long watch.
- `list` — list the OpenCode panes this tool owns, with their session id.
- Optionally `attach` — print the `zellij attach <session>` command.

## Proposed approach

1. Add the subcommands to `zellij-llm.sh` (argc `@cmd` functions) and to the
   test file (`zellij_llm_test.py`).
2. Reuse the existing spawn machinery: the derived session name, the run
   marker, the stacked layout. Wrap the command so it enters the project's
   devenv first. Detect devenv with `devenv.nix`/`devenv.yaml` in the cwd (or a
   `--devenv` flag); run `devenv shell -- opencode` when present.
3. `send` focuses the pane (or uses the pane id from the run marker) and writes
   the text plus a carriage return. Keep the text out of the shell trace (the
   spawn runs under `bash -x`, which leaks a literal secret; a prompt is not a
   secret, but keep the same care).
4. `watch` samples the pane like the manual monitor: RUNNING while the OpenCode
   "esc interrupt" indicator is present, IDLE when it is gone, and an error scan.
   Log transitions. Stop on idle, on an error, or at `--for`.
5. Keep the OpenCode session id: parse it from the pane (`ses_<id>` in the
   status line) so `list` and `send` can name a session.

## Open questions

- How to detect "turn finished" robustly. The manual monitor uses the
  "esc interrupt" indicator. Confirm it is stable across OpenCode versions.
- How to read the session id without a full scrollback parse. A title or an
  environment variable may be cleaner.
- Whether `send` should target a pane by slug, by OpenCode session id, or both.
- Whether to reuse the `zellij-llm` session (one session, many panes) or give
  each OpenCode session its own zellij session.
- devenv activation: `devenv shell -- opencode` starts a nested shell; confirm
  the TUI keys and the wrapper env reach it.

## References

- `packages/llm/zellij-llm/zellij-llm.sh`, `zellij_llm_test.py`, `default.nix`.
- [docs/mcpsnoop.md](../../../docs/mcpsnoop.md) — a sibling TUI tool in this repo.
- `.agents/skills/zellij/SKILL.md` — the zellij rules this must respect.
- The manual monitor this generalizes: `/tmp/opencode/ee324-monitor.sh`
  (session `main`, pane 0, OpenCode session `ses_ee324b411ffe1JJtR5p4wl7I6Z`).
