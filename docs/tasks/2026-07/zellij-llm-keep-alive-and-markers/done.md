---
type: Task
description: Solution — a zellij-llm pane drops to an interactive shell after its command exits, so the session stays alive, and wait/watch detect completion with a per-run file marker under the cache root.
status: done
authored_by: agent
timestamp: 2026-07-31T18:30:00+02:00
---

# Solution — keep sessions alive; detect completion with file markers

## Root cause analysis

A zellij session dies when all its panes' processes end. `zellij-llm spawn` ran the fed command
as the pane's only process. When the command ended, the pane process ended, and the session went
EXITED. The user could not attach later to review the output.

The redesign in [[zellij-llm-derive-names-from-kdn-slug]] added a persist flag, but its exit
detection still read the `list-panes` exited flag. A persisted pane never reports exited, so that
signal was unreliable under keep-alive.

## Solution

- **Drop to a shell.** The spawn wrapper is
  `<cmd>; rc=$?; printf '%s' "$rc" > <marker>; exec "${SHELL:-bash}" -i`. After the command exits,
  the pane replaces itself with the user's login shell (interactive). A live process holds the
  pane, so the session stays up and attachable. The output above the prompt is retained (verified
  with bash and zsh). The single quotes that defer `$rc`/`$SHELL` to the pane's bash are
  deliberate; `SC2016` is excluded in `default.nix`.
- **Ephemeral opts out.** `--ephemeral` uses `exit "$rc"` plus zellij's `--close-on-exit`. The
  pane closes the moment its command exits and is not reviewable. This is the rare case.
- **File marker, not stdout sentinel.** Each run gets its own directory. The wrapper writes the
  command exit code to `<run-dir>/exit`. `wait`/`watch` poll that file (`_pane_done` checks it
  exists; `wait` reads the code). File markers were rejected against sentinels because sentinels
  are lossy (finite scrollback), the `-x` trace echoes them, build output can false-match, and
  parsing terminal text is fragile. The marker survives after the spawning process is gone.
- **Deterministic cache layout.** The run directory is
  `<repo>/.cache/zellij-llm/<cmd-name>/<cmd-id>/` inside a git repo (`_repo_root` walks up for
  `.git`), else `${XDG_CACHE_HOME:-$HOME/.cache}/zellij-llm/<cmd-name>/<cmd-id>/`
  (`_cache_root`). `<cmd-id>` is `<timestamp>-$RANDOM` (`_new_cmd_id`), so lexical order equals
  chronological order and the newest run is the maximum (`_latest_cmd_dir`). `<cmd-name>` is the
  pane name, sanitized (`_sanitize`).
- **Marker resolution.** `spawn --wait` passes the exact marker it created. A standalone
  `wait`/`watch` resolves the pane reference to a name, then reads the newest run's marker
  (`_marker_for_ref`). Both error early when no marker exists.
- **`.gitignore`.** `/.cache/` is ignored, because the tool writes run markers under
  `<repo>/.cache/zellij-llm/`.

## Verification steps

- `nix build .#packages.aarch64-darwin.zellij-llm.tests.pytest` — 15 tests pass, including
  `test_session_survives_after_command_exits` (session is not EXITED and the output is still
  present after the command finishes) and `test_run_marker_written_under_cache` (marker written
  to `<cache>/zellij-llm/<pane>/<run>/exit` with the right exit code).
- Manual, end to end: a real spawn stayed LIVE after its command exited, dropped to the user's
  shell, and a separate `wait` invocation read the marker and returned the exit code.

## Follow-up notes

- Built on [[zellij-llm-derive-names-from-kdn-slug]] and [[zellij-llm-docs-clarity]]. Those tasks
  removed the `_pane_exit_status` reader; all completion detection now goes through the marker.
