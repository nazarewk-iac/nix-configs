---
type: Task
description: Solution — zellij-llm is simpler to use: derived names, persist-by-default panes, watch/wait subcommands, early socket-length error, and a matching skill doc.
status: done
authored_by: agent
timestamp: 2026-07-31T14:45:00+02:00
---

# Solution — make zellij-llm clearer to use

## Root cause analysis

Driving a long command through `zellij-llm` took too much ceremony. The friction points were not
obvious until you hit them: a two-step name dance (`kdn-slug` then `--session`), a late socket
length failure with a cryptic message, and no first-class wait affordance (so an agent fell back
to a `sleep`+`peek` poll loop). The help text and the skill doc still described the old
`--session`-first pattern.

## Solution

- **Derived names, minimal call.** `zellij-llm spawn --pane <slug>` works with no `--session`
  (see [[zellij-llm-derive-names-from-kdn-slug]]). The two-step name dance is gone.
- **Early socket-length error.** `_validate_socket_len` checks the full IPC socket path before
  `spawn` and prints an actionable message, instead of failing deep inside zellij.
- **Persist by default.** `spawn` and `spawn --wait` keep the pane open after the command exits,
  so the user can attach and review. `--ephemeral` opts into `--close-on-exit`.
- **`-x` trace and the secrets caveat.** Commands still run under `bash -xeEuo pipefail`. The
  `-x` trace shows which command to re-run from a persisted pane. The skill and the top-level
  `--help` warn that a secret in a literal argument leaks into the pane scrollback.
- **Wait/watch affordances instead of `sleep`+`peek`:**
  - `watch --pane <ref>` follows an already-spawned pane until its command exits (stream or
    heartbeat).
  - `wait --pane <ref>` blocks until the command exits, prints `EXIT:<code>`, and returns that
    code with no output stream.
  - `spawn --wait` is a modifier equal to `spawn-and-watch`. `spawn-and-watch` stays for
    compatibility.
  - `watch`/`wait` read the exit status from `list-panes` (`_pane_exit_status`) when there is no
    exit-marker file; `spawn --wait` still uses the private marker file.
- **Short pane slugs.** `_check_slug` warns (does not fail) when a `--pane` name is long or has
  spaces, so it reads well in `list`/`peek` output and the title bar.
- **Tighter help.** `@describe` shows the minimal invocation, the HEREDOC style, and the secrets
  caveat. Each subcommand documents its flags.
- **Skill doc updated.** `.agents/skills/zellij/SKILL.md` drops the manual `kdn-slug names`
  pre-step, documents the six subcommands, `--wait`, `--ephemeral`, and the "do not
  `sleep`+`peek`" rule. It stays in strict Simple Technical English.

## Verification steps

- `zellij-llm --help` shows the minimal `spawn --pane <slug>` invocation and the six subcommands.
- `nix build .#packages.aarch64-darwin.zellij-llm.tests.pytest` — 13 tests pass, including
  `test_spawn_persists_pane_by_default`, `test_spawn_ephemeral_closes_pane_on_exit`,
  `test_spawn_wait_stream_matches_spawn_and_watch`, `test_watch_follows_existing_pane_to_exit`,
  and `test_wait_blocks_until_exit_and_returns_code`.
- Manual: heartbeat, stream, `watch` on an existing pane, `wait`, and `--ephemeral` all behave as
  documented against a scratch session.

## Follow-up notes

- Committed with [[zellij-llm-derive-names-from-kdn-slug]] as
  `feat(zellij-llm): derive session name from kdn-slug; add watch/wait + persist-by-default`
  (change `kkxrzzxx`).
- The `zellij-llm` package is still not in the Bash permission allowlist, so its state-change
  calls still prompt. That is unchanged by this task.
