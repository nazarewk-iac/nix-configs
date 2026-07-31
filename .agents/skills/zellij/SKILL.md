---
name: zellij
description: Read command output from the user's own zellij panes (only when the user asks, confirmed per-pane). Otherwise run your own commands in a dedicated background zellij session and do not touch theirs. Use this skill when the user asks you to check or read output from "the terminal", "my pane/session", or a long-running command, or when you must run a long-running command yourself.
type: Skill
timestamp: 2026-07-29T16:03:22+02:00
---

## The one rule that matters

Do not change the user's zellij session. Do not read the content of a pane. Do these two things
only when the user tells you to.

These actions change a session: a new tab, a new pane, a focus change (`go-to-tab`,
`focus-pane-id`), a close, a rename, `kill-session`, and `delete-session`. These actions read the
content of a pane: `dump-screen`, `subscribe`, and `edit-scrollback`. Do your own work in a
dedicated session (see below).

There is one exception. Discovery is safe. You can list the sessions, tabs, panes, and clients
before you ask. These commands do not show pane content: `list-sessions`, `action list-tabs`,
`action list-panes`, `action list-clients`, and `action current-tab-info`. Use them to find the
pane that the user means. Then ask to read it.

This rule is necessary. A zellij session is shared and stateful, and the focus follows the
action. A `new-tab`, a `go-to-tab`, or a `close-tab` changes what the user sees. It can also take
keystrokes from the user. For example, it can take an answer to a permission prompt. Pane content
can show any user action. The user does not always want this content in the conversation. You
cannot undo a close. You cannot recover the scrollback of a closed pane.

## Read the user's session

Discovery does not need a question first. Use it to find the correct pane:

```bash
zellij list-sessions -s                               # session names only
zellij --session main action list-tabs -a --json       # tabs: id, name, active, pane counts
zellij --session main action list-panes -a --json      # panes: id, title, tab, exited, focused
zellij --session main action list-clients              # attached clients
zellij --session main action current-tab-info --json   # active tab of that session
```

The pane `id` from `list-panes` is a plain integer. An action command accepts the plain integer,
`terminal_<id>`, or `plugin_<id>`. A plain integer is a terminal. Use `title`, `terminal_command`,
or `tab_name` from the JSON to find the pane that the user means. For example, find "the build
output" or "the pane that runs the tests".

A content read is the sensitive part. Always ask the user first. Ask first even when the request
is general. For example, ask first for "check my terminal". Name the session, the pane, and the
tab that you will read. Then wait for the user to agree. For example: "That is pane 11, `hx` in
your `nix` tab, session `main`. Do I read it now?"

```bash
# viewport only (what is currently visible) - fast, small
zellij --session main action dump-screen -p 11
# full scrollback - can be thousands of lines, pipe through tail/grep
zellij --session main action dump-screen -p 11 -f | tail -100
zellij --session main action dump-screen -p 11 -f | grep -i error
# keep ANSI colors when you must relay styled output
zellij --session main action dump-screen -p 11 -f -a
# write to a file instead of stdout (good for a very large dump)
zellij --session main action dump-screen -p 11 -f --path /tmp/pane-11.txt
```

`dump-screen` captures only the viewport by default. It does not capture the scrollback. Use `-f`
(or `--full`) when you need the history. For example, use `-f` to see a full build log. Also use
`-f` to see the start of a long-running command.

Use `subscribe` for a live read instead of a snapshot. The same rule applies: ask the user first.

```bash
zellij --session main subscribe -p 11 --format json --scrollback 200
```

`subscribe` sends NDJSON events when the pane changes. Use it for "tell me when this stops". Do
not use a `dump-screen` loop for this.

## Run your own commands: use `kdn-slug` and `zellij-llm`

You sometimes need to run a command, not read output. This matters most for a long-running
command. Run it in your own zellij session. Do not run it in the user's session. Do not run it in
a "new" tab in the user's session. A new tab moves the user's focus to that tab immediately. You
must prevent this interruption.

Two packages do this work for you. Use them. Do not write raw
`zellij attach --create-background`, `action new-pane`, or `subscribe` calls yourself.

- `zellij-llm` (`packages/llm/zellij-llm/`) is the tool you call. It has six subcommands:
  `spawn`, `spawn-and-watch`, `watch`, `wait`, `peek`, and `list`. It derives the session name
  itself (see below), so `--session` is optional. It creates the session (idempotent). It makes
  the stacked-pane layout. It runs the command from stdin with `bash -xeEuo pipefail`. Run
  `zellij-llm --help` or `zellij-llm <subcommand> --help` for all flags.
- `kdn-slug` (`packages/llm/kdn-slug/`) makes the names. `zellij-llm` calls it for you. You
  rarely call it directly. It finds the repository with `jj` or `git`. It finds the session id of
  the current harness. For example, it reads `$CLAUDE_CODE_SESSION_ID`. It has a top-level
  separator `--sep` (default `:`), a repo-path separator `--repo-sep` (default `_`), and a
  `--max-len` limit. `zellij-llm` forwards `--sep`, `--repo-sep`, `--max-len`, and `--tag` to it.

`zellij-llm` derives the default session name from `kdn-slug`. It caps the name to fit zellij's
socket-path limit. So the minimal call is `zellij-llm spawn --pane <slug>` with no `--session`.
Pass `--session <name>` to override the derived name; the tool then uses your name verbatim. Pass
`--tag <slug>` (repeatable) to add trailing components to the derived name.

Feed the command to `zellij-llm` with a HEREDOC. Do not use `echo ... | zellij-llm`. A HEREDOC
reads more clearly in the permission prompt. It also handles a multi-line command well.

```bash
# a. spawn — run and return. It derives the session name when you omit --session. It creates the
#    session when no session exists yet. It runs the command (from stdin) in a new pane. It folds
#    the pane into the stack. The pane stays open after the command exits. spawn returns at once.
zellij-llm spawn --pane 'darwin-build' <<'EOF'
darwin-rebuild build
EOF

# spawn --wait — spawn, then follow the pane until the command exits. Same as spawn-and-watch.
#    --mode stream:    it forwards the live pane output to this call's stdout.
#    --mode heartbeat: it prints an elapsed-time status line at each --interval.
zellij-llm spawn --pane 'flake-update' --wait --mode stream <<'EOF'
nix flake update
EOF

# b. spawn-and-watch — the same as spawn --wait. It exists for compatibility.
zellij-llm spawn-and-watch --pane 'flake-update' --mode heartbeat --interval 5 <<'EOF'
nix flake update
EOF
# every wait mode prints a final "EXIT:<code>" line and exits with that same code

# c. watch — follow a pane you spawned earlier until its command exits. Same output modes as
#    spawn --wait. Use it to attach to a still-running pane without a re-spawn.
zellij-llm watch --pane 'darwin-build' --mode stream

# d. wait — block until a pane's command exits. Print "EXIT:<code>" and return that code. No
#    output stream. Use `spawn` then `wait` instead of a `sleep`+`peek` loop.
zellij-llm wait --pane 'darwin-build'

# e. peek — dump the content of a pane in your own session (viewport, or --full for scrollback).
#    This is the one exception to "ask first for a content read". peek works only on your own
#    session. Use it freely on your own work, like the discovery commands above.
zellij-llm peek --pane 'darwin-build' --full

# f. list — list the panes (id, title, exited, exit_status, command) in your own session.
zellij-llm list
```

Do not poll with `sleep N; zellij-llm peek`. Use `wait`, `watch`, or `spawn --wait` instead. A
poll wastes time or reads a half-finished log.

`spawn` keeps the pane open after the command exits, so you can review the output later. Pass
`--ephemeral` to close the pane the moment its command exits.

The command runs under `bash -xeEuo pipefail`. The `-x` trace echoes each command into the pane.
This shows exactly which command to re-run from a persisted pane. But `-x` also echoes a secret
in a literal argument. For example, `--password abc` or `FOO=$TOKEN cmd` leaks into the pane
scrollback and into any `peek`/`watch` output. Pass a secret through a file or a named env var,
not a literal value. Or wrap the sensitive step: `{ set +x; ...; set -x; } 2>/dev/null`.

`zellij-llm` uses this naming convention. Do not use a generic name like `agent-work`. Use a
short kebab-case slug for each `--pane` (for example, `darwin-build`), not a full sentence.

- Session: `llm:<repo-slug>:<llm-session-id>[:<slug1>:<slug2>...]`. The `<repo-slug>` shows the
  repository that the work belongs to. The `<llm-session-id>` ties the work to the agent
  conversation that made it. The optional extra slugs add more detail. `zellij-llm` derives this
  name for you and caps it to fit the socket-path limit. It shortens the `<repo-slug>` or the
  `<llm-session-id>` as needed. So the real name is sometimes a shorter form, for example
  `llm:nix-configs:deadbeef`. The `<repo-slug>` is the full `<host>_<org>_<repo>` at full length.
  For example, it is `github.com_nazarewk-iac_nix-configs`. The top level joins with `:`
  (`--sep`). The repo path parts join with `_` (`--repo-sep`, a separate delimiter). Each `--tag`
  adds a slug to the end of the name. The repo separator is `_`, not `/`. zellij does not accept
  `/` in a session name (`Session name cannot contain '/'.`). zellij accepts every other
  punctuation character that was tested. Override `--repo-sep` when `_` is a problem for your
  names.
- Tab (for several sub-agents in one session): `<agent-slug>:<slug1>...`. A sub-agent can open
  many tabs. Every tab must start with that sub-agent's own `<agent-slug>`. Then it can add more
  slugs for the specific work. This keeps each tab attributable to the sub-agent that made it,
  even when several sub-agents share one session. `kdn-slug names --type tab --tag <agent-slug>
  --tag <slug> ...` makes this name. `zellij-llm` manages panes, not tabs. Use a raw `zellij
  action new-tab --name "$TAB"` call in your own session to make a tab.
- Pane: use a short slug for the purpose of the pane. For example, use `darwin-build`. Pass it as
  the `--pane` value of `zellij-llm`. You do not need `kdn-slug` for a pane name.

This convention lets `zellij list-sessions` and `list-tabs` show clearly which session and tab
belong to which repository and conversation.

`zellij-llm spawn` and `spawn-and-watch` fold each new pane into the stack for you. A raw
`new-pane --stacked` fails without an error in a headless session with no attached client. They
also leave the pane open after the command stops. The user may want to read the output later.
Close or rename a pane in your own session only with a raw `zellij action ...` call. Do it only
when you are sure that the pane is no longer useful. When you are not sure, leave the pane for the
user.

### Let the user watch or attach

Tell the user at the start of any work that uses a dedicated session. Tell the user that you use a
dedicated session. Tell the user how to open it. Do not assume that the user watches. `zellij-llm
spawn` prints the session name it used (`spawned pane '<pane>' in session '<name>'`). Use that
real name. For example, use `llm:nix-configs:c8a27b8a`. Do not use a placeholder:

> I run this in a separate zellij session (`llm:nix-configs:c8a27b8a`), not your active one.
> To watch it live, open a new terminal window and run:
> `zellij attach llm:nix-configs:c8a27b8a`

Keep this generic. Do not assume a specific terminal emulator. The user's terminal is sometimes
WezTerm. Then the user can open a new window that runs the attach command directly:

```bash
# quote the session name — it has ':' and '_', and the shell treats some punctuation as special
SESSION='llm:nix-configs:c8a27b8a'                     # the name that spawn printed
wezterm start --new-tab -- zellij attach "$SESSION"    # new tab in the current window
wezterm start -- zellij attach "$SESSION"              # new standalone window
```

## Quick reference

This repository sets `kdn.zellij.enable = true` through
[modules/slots/zellij/](../../../modules/slots/zellij/default.nix). Any repository that does the
same gets this behavior. The "Pre-allowed" rows below have a Claude Code `Bash` permission
allowlist entry. No prompt appears for them. Every other command has no allowlist entry. Claude
Code always prompts for those, as the rule above requires.

| Command | Purpose | On the user's session |
|---|---|---|
| `zellij list-sessions*` | List session names | Pre-allowed (no prompt) |
| `action list-panes *` (optional `--session *`) | Pane ids, titles, tab, exited state | Pre-allowed (no prompt) |
| `action list-tabs *` (optional `--session *`) | Tab ids, names, active/focus state | Pre-allowed (no prompt) |
| `action list-clients*` (optional `--session *`) | Attached clients | Pre-allowed (no prompt) |
| `action current-tab-info*` (optional `--session *`) | Info about the active tab | Pre-allowed (no prompt) |
| `attach --create-background *` | Create or reuse a detached session of your own | Pre-allowed — creates only your session |
| `action dump-screen -p <id> [-f] [-a]` | Snapshot pane viewport or scrollback | Not allowlisted — always prompts. Ask the user which pane first, every time |
| `subscribe -p <id> --format json` | Stream pane updates (NDJSON) | Not allowlisted — always prompts. Ask first |
| `edit-scrollback` | Open scrollback in `$EDITOR` | Not allowlisted — always prompts. Ask first |
| `action new-pane` / `new-tab` / `go-to-tab*` / `focus-pane-id` / `close-*` / `kill-session` | Create, focus, or destroy state | Not allowlisted — always prompts. Never do this on the user's session. Do it in your own session |
| `action new-pane --stacked --name <n> -- <cmd>` (your own session) | Run a command in a new stacked pane | Still prompts (not allowlisted). This is correct: it changes state, even in your own session |
| `kdn-slug names --type <session\|tab\|pane> ...` | Make the naming-convention strings above | Read-only, no allowlist needed |
| `zellij-llm spawn` / `spawn-and-watch` / `watch` / `wait` / `list` (your own session) | Preferred wrapper for the state-change calls above | Prompts the same as the raw calls. Not yet in the Bash allowlist |
| `zellij-llm peek` (your own session) | Preferred wrapper for `action dump-screen` | Like `dump-screen` above, but works only on your own session |

## Gotchas

- `dump-screen` captures only the viewport by default. Pass `-f` for the scrollback and the
  history.
- A pane id is a plain integer, `terminal_<id>`, or `plugin_<id>`. Plugins (the status bar and the
  tab bar) also appear in `list-panes`. Filter on `"is_plugin": false` to get the real terminals.
- `new-tab`, `go-to-tab`, and `close-tab` change the focus for every attached client immediately.
  For this reason, you must not run them on the user's session, not even to peek.
- Concurrent writes (`write`, `write-chars`, `paste`, `send-keys`) to one pane can mix in an
  unpredictable order. A read (`dump-screen`, `list-panes`) is safe at the same time as any other
  command.
- `paste` (bracketed paste) is more reliable than `write-chars` for multi-line input. Use it when
  you must send input to a pane in your own session.
- `zellij attach --create-background <name>` exits with code 1 when the session is already
  present. It also prints `Session already exists` on stderr. This is a no-op, but the exit code
  is not 0. `zellij-llm` handles this internally. Do not assume that `&& echo ok` works after a
  raw `attach --create-background` call.
- `action new-pane --stacked` does nothing in a headless session with no attached client. It
  returns a pane id. But the pane never appears in `list-panes`, and `dump-screen` on it returns
  empty. `zellij-llm` handles this with a plain `new-pane` and then `action stack-panes`. This is
  a problem only when you write a raw `zellij action ...` call instead of `zellij-llm spawn` or
  `spawn-and-watch`.
- `subscribe` never stops by itself, not even after the pane's command stops. It stops the events,
  but it blocks forever. `zellij-llm spawn-and-watch --mode stream` handles this. It polls a
  separate exit marker. It stops `subscribe` when the marker appears. A raw `zellij subscribe ...`
  call in a script needs the same logic, or a timeout.
