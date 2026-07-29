---
name: zellij
description: Read command output from zellij panes the user is interacting with (only on their explicit request, confirmed per-pane), and otherwise run your own commands in a dedicated background zellij session without touching theirs. Use whenever the user asks you to check/read output from "the terminal", "my pane/session", or a long-running command they're watching, or when you need to run something long-running yourself.
type: Skill
timestamp: 2026-07-29T16:03:22+02:00
---

## The one rule that matters

**Never mutate the user's zellij session, and never read a pane's actual content, unless they
explicitly ask you to.** Mutation covers everything: new tabs, new panes, focus changes
(`go-to-tab`, `focus-pane-id`, ...), closes, renames, `kill-session`/`delete-session`. Content
reads (`dump-screen`, `subscribe`, `edit-scrollback`) covers anything that shows you what's
*inside* a pane. Do your own work in a dedicated session instead (see below).

**Exception — pure discovery/metadata is fine without asking first:** listing what
sessions/tabs/panes exist (`list-sessions`, `action list-tabs`, `action list-panes`,
`action list-clients`, `action current-tab-info`) doesn't reveal pane content and is safe to run
proactively, e.g. to figure out which pane the user means before asking to read it.

This rule exists because zellij sessions are shared, stateful, and focus-following: actions like
`new-tab`/`go-to-tab`/`close-tab` change what *the user* is looking at and can steal keystrokes
they're mid-typing (e.g. answering a permission prompt), and pane content can include anything
the user is doing — not necessarily something they want relayed into this conversation. There is
no dry-run and no undo for a closed pane's scrollback.

## Reading the user's session

Discovery (tabs/panes/sessions/clients) needs no per-step confirmation — use it freely to locate
the right pane:

```bash
zellij list-sessions -s                               # session names only
zellij --session main action list-tabs -a --json       # tabs: id, name, active, pane counts
zellij --session main action list-panes -a --json      # panes: id, title, tab, exited, focused
zellij --session main action list-clients              # attached clients
zellij --session main action current-tab-info --json   # active tab of that session
```

`list-panes` pane `id` is a bare integer; action commands accept it directly or as
`terminal_<id>` / `plugin_<id>` (bare integer == terminal). Use `title`/`terminal_command`/
`tab_name` from the JSON to identify *which* pane the user means ("the build output", "the pane
running tests").

**Content reads are the sensitive part — always get explicit confirmation first**, even if the
user's original ask was somewhat general ("check my terminal"): name the specific
session/pane/tab you're about to read and wait for a go-ahead (e.g. "that's pane 11, `hx` in
your `nix` tab, session `main` — read it now?").

```bash
# viewport only (what's currently visible) - fast, small
zellij --session main action dump-screen -p 11
# full scrollback - can be thousands of lines, pipe through tail/grep
zellij --session main action dump-screen -p 11 -f | tail -100
zellij --session main action dump-screen -p 11 -f | grep -i error
# preserve ANSI colors if you need to relay styled output
zellij --session main action dump-screen -p 11 -f -a
# write to a file instead of stdout (useful for very large dumps)
zellij --session main action dump-screen -p 11 -f --path /tmp/pane-11.txt
```

`dump-screen` without `-f`/`--full` only captures the visible viewport, not scrollback — pass
`-f` whenever you need history, e.g. to see a full build log or the start of a long-running
command.

For live/streaming reads instead of point-in-time snapshots (same confirm-first rule applies):

```bash
zellij --session main subscribe -p 11 --format json --scrollback 200
```

Emits NDJSON events as the pane updates — useful for "tell me when this finishes" instead of
polling `dump-screen` in a loop.

## Running commands yourself: use a dedicated session, not the user's

If you need to run a command (especially anything long-running) rather than just read existing
output, do it in your own zellij session — never inside the user's attached session, even in a
"new" tab there (creating a tab switches the user's focus to it immediately, which is exactly
the kind of interruption to avoid).

```bash
# create (or reuse) a detached background session dedicated to agent work
zellij attach --create-background agent-work
```

`--create-background` creates the session detached if it doesn't exist yet, and is a no-op if it
already does — safe to call every time before use. Pick a session name that says it's yours
(e.g. `agent-work`, `agent-<task>`) so it's never mistaken for a user session.

Within that session, prefer **stacked, named panes** over a fresh tab per command, and leave
them open after the command finishes rather than closing them — the user may want to review the
output later:

```bash
zellij --session agent-work action new-pane --stacked --name 'build: darwin-rebuild' \
  -- darwin-rebuild build
```

Check progress/output the same way as above (`dump-screen`, `list-panes --json`), targeting
`--session agent-work`. Only close/rename panes in your own session, and only when you're sure
they're no longer useful — when in doubt, leave them for the user to inspect.

### Letting the user watch or attach

Tell the user, at the start of any work that uses a dedicated session, that you're using one and
how to open it themselves — don't assume they're watching:

> I'm running this in a separate zellij session (`agent-work`), not your active one. To watch
> live, open a new terminal window and run:
> `zellij attach agent-work`

Keep this generic — don't assume a specific terminal emulator. If the user's terminal happens to
be WezTerm, they can also spawn a fresh window running that attach command directly:

```bash
wezterm start --new-tab -- zellij attach agent-work    # new tab in the current window
wezterm start -- zellij attach agent-work               # new standalone window
```

## Quick reference

In this repo (and any repo pulling in `kdn.zellij.enable = true` via
[modules/slots/zellij/](../../../modules/slots/zellij/default.nix)), the "Pre-allowed" rows below
are backed by an actual Claude Code `Bash` permission allowlist — no prompt appears for them.
Everything else deliberately has **no** allowlist entry, so Claude Code always prompts for user
consent, matching the rule above:

| Command | Purpose | On the user's session |
|---|---|---|
| `zellij list-sessions*` | List session names | Pre-allowed (no prompt) |
| `action list-panes *` (optionally `--session *`) | Pane ids, titles, tab, exited state | Pre-allowed (no prompt) |
| `action list-tabs *` (optionally `--session *`) | Tab ids, names, active/focus state | Pre-allowed (no prompt) |
| `action list-clients*` (optionally `--session *`) | Attached clients | Pre-allowed (no prompt) |
| `action current-tab-info*` (optionally `--session *`) | Info about the active tab | Pre-allowed (no prompt) |
| `attach --create-background *` | Create/reuse a detached session of your own | Pre-allowed — only ever creates *your* session |
| `action dump-screen -p <id> [-f] [-a]` | Snapshot pane viewport/scrollback | **Not allowlisted — always prompts. Confirm which pane with the user first anyway, every time** |
| `subscribe -p <id> --format json` | Stream pane updates (NDJSON) | **Not allowlisted — always prompts. Confirm first** |
| `edit-scrollback` | Open scrollback in `$EDITOR` | **Not allowlisted — always prompts. Confirm first** |
| `action new-pane` / `new-tab` / `go-to-tab*` / `focus-pane-id` / `close-*` / `kill-session` | Create, focus, or destroy state | **Not allowlisted — always prompts. Never do this on the user's session regardless of the prompt; do it in your own session instead** |
| `action new-pane --stacked --name <n> -- <cmd>` (in your own session) | Run a command in a new stacked pane | Still prompts (not allowlisted) — expected, since it mutates state, even though it's your own session |

## Gotchas

- `dump-screen` defaults to viewport-only; always pass `-f` for scrollback/history.
- Pane ids can be bare integers, `terminal_<id>`, or `plugin_<id>` — plugins (status bar, tab
  bar) show up in `list-panes` too; filter on `"is_plugin": false` when you want real terminals.
- `new-tab`/`go-to-tab`/`close-tab` immediately change what's focused for *every* attached
  client — this is why they're forbidden on the user's session even "just to peek".
- Concurrent writes (`write`, `write-chars`, `paste`, `send-keys`) to the same pane can interleave
  unpredictably; reads (`dump-screen`, `list-panes`) are safe to run concurrently with anything.
- `paste` (bracketed paste) is more reliable than `write-chars` for multi-line input if you ever
  need to send input to a pane in your own session.
