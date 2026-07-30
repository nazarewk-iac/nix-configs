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

## Running commands yourself: use `kdn-slug` + `zellij-llm`, not raw `zellij action ...`

If you need to run a command (especially anything long-running) rather than just read existing
output, do it in your own zellij session — never inside the user's attached session, even in a
"new" tab there (creating a tab switches the user's focus to it immediately, which is exactly
the kind of interruption to avoid).

**Two purpose-built packages exist for this — reach for them instead of hand-rolling
`zellij attach --create-background`/`action new-pane`/`subscribe` calls:**

- **`kdn-slug`** (`packages/llm/kdn-slug/`) generates the session/tab/pane names described
  below — auto-discovers the repo (via `jj`/`git`) and the current harness's session id (e.g.
  `$CLAUDE_CODE_SESSION_ID`), with override flags, a top-level `--sep` (default `:`), a repo-path
  `--repo-sep` (default `_`), and an optional `--max-len` truncation fallback. Run
  `kdn-slug --help` / `kdn-slug <subcommand> --help` for the full flag reference.
- **`zellij-llm`** (`packages/llm/zellij-llm/`) wraps session creation, pane spawning, output
  streaming/heartbeating, and pane-content reads into four subcommands: `spawn`,
  `spawn-and-watch`, `peek`, `list`. It handles the idempotent session creation, stacked-pane
  layout, and stdin-fed command execution (via `bash -xeEuo pipefail`) that used to require
  several raw `zellij action ...` calls. Run `zellij-llm --help` / `zellij-llm <subcommand>
  --help` for the full flag reference.

```bash
# generate this conversation's session name once, reuse it for every zellij-llm call below
SESSION="$(kdn-slug names --type session)"          # e.g. llm:github.com_nazarewk-iac_nix-configs:c8a27b8a-...
TAB="$(kdn-slug names --type tab --tag my-subagent)"  # e.g. my-subagent (tabs are opt-in; zellij-llm itself only manages panes, not tabs)

# a. spawn — fire-and-forget: creates the session if missing, runs a command (fed via THIS
#    invocation's stdin) in a new pane, folds it into the existing stack, and returns immediately
echo 'darwin-rebuild build' | zellij-llm spawn --session "$SESSION" --pane 'build: darwin-rebuild'

# b. spawn-and-watch — like spawn, but follows the pane until the command exits
#    --mode stream:    forwards live pane output to this call's stdout as it arrives
#    --mode heartbeat: prints periodic elapsed-time status lines instead of full output
echo 'nix flake update' | zellij-llm spawn-and-watch --session "$SESSION" --pane 'flake-update' --mode stream
echo 'nix flake update' | zellij-llm spawn-and-watch --session "$SESSION" --pane 'flake-update' --mode heartbeat --interval 5
# both modes print a final "EXIT:<code>" line and exit with that same code

# c. peek — dump a pane's own-session content (viewport, or --full for scrollback) — this is
#    the ONE exception to "content reads always need confirmation": it's scoped to your OWN
#    session by design (never pass a session name you don't own), so it's safe to use freely
#    to check on your own spawned work, same as the discovery commands above
zellij-llm peek --session "$SESSION" --pane 'build: darwin-rebuild' --full

# d. list — inventory panes (id, title, exited, exit_status, command) in your own session
zellij-llm list --session "$SESSION"
```

**Naming convention `kdn-slug`/`zellij-llm` implement — never use a generic name like
`agent-work`:**

- **Session:** `llm:<repo-slug>:<llm-session-id>[:<optional-slug1>:<optional-slug2>...]`.
  `<repo-slug>` identifies which repo the work belongs to; `<llm-session-id>` ties it to the
  specific agent conversation that created it; trailing optional slugs disambiguate further.
  `kdn-slug names --type session [--tag <slug> ...]` generates this. `<repo-slug>` is
  fully-qualified `<host>_<org>_<repo>` (e.g. `github.com_nazarewk-iac_nix-configs`) — the top
  level joins on `:` (`--sep`) while the repo path parts join on `_` (`--repo-sep`, a *separate*
  delimiter). The repo separator defaults to `_` rather than `/` because **zellij rejects `/`
  in session names outright** (`Session name cannot contain '/'.`); every other punctuation
  char tested is accepted, so `--repo-sep` can be overridden if `_` collides with your names.
- **Tab** (supports multiple sub-agents sharing one session): `<agent-slug>:<slug1>...` — a
  sub-agent may open any number of tabs, but every one of them must carry that sub-agent's own
  `<agent-slug>` prefix (plus whatever further slugs describe each tab's specific work), so tabs
  stay attributable to the sub-agent that created them even when several sub-agents share one
  session. `kdn-slug names --type tab --tag <agent-slug> --tag <slug> ...` generates this — note
  `zellij-llm` itself only manages panes, not tabs, so tab creation (if you use one) is still a
  raw `zellij action new-tab --name "$TAB"` call in your own session.
- **Pane:** a short slug describing the pane's purpose is fine as-is (e.g. `build: darwin-rebuild`,
  passed directly as `zellij-llm`'s `--pane` value — no `kdn-slug` involvement needed).

This makes `zellij list-sessions`/`list-tabs` unambiguously show whose session/tab is whose and
which repo/conversation it belongs to.

`zellij-llm spawn`/`spawn-and-watch` already fold each new pane into the session's existing
stack for you (working around a zellij quirk where `new-pane --stacked` silently fails in a
headless session with no attached client) and leave panes open after the command finishes
rather than closing them — the user may want to review the output later. Only close/rename
panes in your own session yourself via raw `zellij action ...`, and only when you're sure
they're no longer useful — when in doubt, leave them for the user to inspect.

### Letting the user watch or attach

Tell the user, at the start of any work that uses a dedicated session, that you're using one and
how to open it themselves — don't assume they're watching. Use the actual value from
`kdn-slug names --type session` (e.g. `llm:github.com_nazarewk-iac_nix-configs:c8a27b8a-...`),
not a placeholder:

> I'm running this in a separate zellij session
> (`llm:github.com_nazarewk-iac_nix-configs:c8a27b8a-...`), not your active one.
> To watch live, open a new terminal window and run:
> `zellij attach llm:github.com_nazarewk-iac_nix-configs:c8a27b8a-...`

Keep this generic — don't assume a specific terminal emulator. If the user's terminal happens to
be WezTerm, they can also spawn a fresh window running that attach command directly:

```bash
# quote the session name — it contains ':' and '_', and shells treat some of the punctuation as special
wezterm start --new-tab -- zellij attach "$SESSION"    # new tab in the current window
wezterm start -- zellij attach "$SESSION"              # new standalone window
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
| `kdn-slug names --type <session\|tab\|pane> ...` | Generate the naming-convention strings above | Read-only, no allowlist needed |
| `zellij-llm spawn` / `spawn-and-watch` / `list` (in your own session) | Preferred wrapper for the mutating calls above | Same prompting as the raw calls they wrap — not yet in the Bash permission allowlist |
| `zellij-llm peek` (in your own session) | Preferred wrapper for `action dump-screen` | Same as `dump-screen` above, but scoped to your own session by construction |

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
- `zellij attach --create-background <name>` exits **1** with `Session already exists` on
  stderr when the session was already there — it is a no-op, but not a zero-exit no-op;
  `zellij-llm` already handles this internally, but don't assume `&& echo ok` after a raw
  `attach --create-background` call.
- `action new-pane --stacked` silently no-ops in a headless session with no attached client:
  it returns a pane id, but the pane never shows up in `list-panes` and `dump-screen` on it
  returns empty. `zellij-llm` works around this (plain `new-pane` + a follow-up
  `action stack-panes`), so this only matters if you're writing a raw `zellij action ...` call
  yourself instead of using `zellij-llm spawn`/`spawn-and-watch`.
- `subscribe` never terminates on its own, even once the subscribed pane's command has already
  exited — it just stops emitting new events and blocks forever. `zellij-llm spawn-and-watch
  --mode stream` handles this by polling a separate exit marker and killing `subscribe` once it
  lands; a bare `zellij subscribe ...` in a script needs the same treatment or a timeout.
