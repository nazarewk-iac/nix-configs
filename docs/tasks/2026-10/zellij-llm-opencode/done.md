---
type: Solution
description: Add a `zellij-llm opencode` command group (spawn/send/watch/list/attach) with devenv activation, tests, and agent-skill docs.
task: definition.md
authored_by: agent
timestamp: 2026-10-10T06:20:00+02:00
---

# `zellij-llm opencode` command group

## Root cause analysis

OpenCode sessions are long-lived TUIs. `zellij-llm` only ran one-shot commands (spawn a command
from stdin, follow it to exit). Driving OpenCode was manual: find the pane, focus it, type a
prompt, press Enter, then watch. The manual monitor written for the `ee324` session on 2026-10-10
proved the value of a first-class command.

argc (the dispatch library `zellij-llm` uses) does support nested subcommands, but with a
`parent::child` function-name syntax and a real parent function. The earlier assumption that it
did not was wrong.

## Solution

Added an `opencode` command group to `packages/llm/zellij-llm/zellij-llm.sh`:

| Command | Behavior |
|---|---|
| `opencode spawn` | Start OpenCode in a new pane. Wraps the command in `devenv shell --` when `devenv.nix`/`devenv.yaml` is present (opt out with `--no-devenv`). `--dry-run` prints the command. `--model`, `--opencode-arg` (repeatable), `--opencode-bin`, `--wait`, `--ephemeral` pass through. |
| `opencode send` | Focus the pane and type a prompt, then Enter (`--no-submit` types only). |
| `opencode watch` | Follow a turn: `state=RUNNING` while OpenCode's `esc interrupt` indicator is present, `state=IDLE` when it is gone; report an error line; return on the first `RUNNING -> IDLE`, or after `--for <duration>` (`30m`, `2h`). |
| `opencode list` | The non-plugin panes and the OpenCode session id (`ses_...`) each shows. |
| `opencode attach` | Print the `zellij attach` command. |

Helpers: `_has_devenv`, `_opencode_command` (quotes with `%q` so the pane's
`bash -xeEuo pipefail` runs it unchanged), `_parse_duration`, `_watch_opencode`,
`_list_opencode`.

Two `set -o pipefail` traps were fixed: a no-match `grep` in a command substitution aborts the
script, so the error-scan and the session-id scan end in `|| true`.

Tests in `zellij_llm_test.py` (a fake OpenCode script run via `bash <path>`, because the sandbox
has no `/usr/bin/env`): `attach`, two `spawn --dry-run` cases (devenv wrap and no-devenv, model
and arg passthrough), `spawn` + `list`, `watch` RUNNING→IDLE, and `send`.

Documented in the zellij agent skill (`.agents/skills/zellij/SKILL.md`): a new
"Drive an OpenCode session" subsection and a quick-reference row.

## Verification steps

```
$ nix build --no-link -L '.#checks.x86_64-linux.zellij-llm-pytest'
21 passed in 22.09s
```

Local smoke test (isolated `ZELLIJ_SOCKET_DIR`, a fake OpenCode):

```
$ zellij-llm opencode spawn --session t1 --pane oc --no-devenv --opencode-bin bash --opencode-arg /tmp/fake
spawned pane 'oc' in session 't1' (run 20261010T060955-28303)
$ zellij-llm opencode list --session t1
0	oc	ses_fake000000000000000000000000
$ zellij-llm opencode spawn --cwd <devenv dir> --dry-run
devenv shell -- opencode
```

## Follow-up notes

- `opencode send` verifies only that it returns 0; the tests do not assert the typed text lands,
  because the fake ignores stdin. A real TUI round-trip is the manual check.
- The `watch` idle signal is the `esc interrupt` indicator. Confirm it stays stable across
  OpenCode versions; a version change could break the heuristic.
- The group uses the same derived session as the other commands, so `spawn`, `send`, and `watch`
  agree on the session when run in the same repository and harness session.
