---
type: Reference
description: Devenv slot module installing zellij and a narrow, consent-preserving Claude Code permission allowlist for it.
timestamp: 2026-07-29T17:03:03+02:00
---

# kdn.zellij

Devenv slot module that installs [zellij](https://zellij.dev) and wires a Claude Code Bash
permission allowlist that covers *only* pure discovery — never pane content reads or session
mutation. Pairs with [.agents/skills/zellij/SKILL.md](../../../.agents/skills/zellij/SKILL.md),
which spells out the consent policy this allowlist implements.

## Options

- `kdn.zellij.enable` — enables the module

## What it does when enabled

- Adds `pkgs.zellij` to `packages`
- Sets `claude.code.enable = lib.mkDefault true` (a default, not a force — a consuming repo can
  still turn Claude Code integration off)
- Installs a narrow `claude.code.permissions.rules.Bash.allow` list (see below)
- Installs `.claude/skills/zellij/SKILL.md` (skipped when `kdn.isSourceRepo` — this repo commits
  the skill directly instead of symlinking it from the Nix store)
- Installs a `zellij-wait-for-devenv` `PreToolUse` hook on `Bash` calls (see below)
- Installs a `zellij-wait-for-devenv-start` `PostToolUse` hook on `Edit`/`MultiEdit`/`Write` calls
  (see below)

## The allowlist, and why it stops where it does

Everything allow-listed is either pure discovery/metadata (reveals no pane content, cannot mutate
state) or a fully static, wildcard-free command that can only ever target the agent's own pane:

| Rule | Why it's safe unprompted |
|---|---|
| `zellij --help` / `zellij help*` / `zellij * --help` | Static help text only |
| `zellij list-sessions*` | Session names only |
| `zellij action list-panes *` (+ `--session *` variant) | Pane ids/titles/tab, no content |
| `zellij action list-tabs *` (+ `--session *` variant) | Tab ids/names/state, no content |
| `zellij action list-clients*` (+ `--session *` variant) | Attached clients, no content |
| `zellij action current-tab-info*` (+ `--session *` variant) | Active tab info, no content |
| `zellij attach --create-background *` | Idempotent; only ever creates/reuses the agent's *own* session, never touches an existing one |
| `` zellij action dump-screen -p "$ZELLIJ_PANE_ID" \| tail -n 1 `` | Exact string, zero wildcards — Claude Code matches the literal, unexpanded command text, so this can only ever read the agent's own pane's last line (e.g. to check an async `devenv` rebuild's status), never an arbitrary pane |

Deliberately **not** allow-listed, so Claude Code always prompts: `dump-screen -p <other>`,
`subscribe`, `edit-scrollback` (any read of pane *content* beyond the one static exception above),
and every mutating action — `new-pane`, `new-tab`, `go-to-tab*`, `focus-pane-id`, `close-*`,
`kill-session`, `delete-session`, `write*`, `paste`, `send-keys`. See the skill for the full
rationale: reading a user's pane content or touching their session state must always be an
explicit, per-action ask, never a standing grant.

## `zellij-wait-for-devenv` hook

`wait-for-devenv.sh` (wrapped by `pkgs.writeShellApplication`, wired as a `PreToolUse` hook
matching `Bash`) delays a tool call while devenv is mid-rebuild in the *same* zellij pane the
agent is running in, so the command doesn't race a half-applied environment reload after editing
`devenv.nix`/`modules/*`.

- Reads `$ZELLIJ_PANE_ID` (own pane) and polls `zellij action dump-screen -p "$ZELLIJ_PANE_ID"`'s
  last line, which is devenv-shell's own status line (`devenv-shell/src/status_line.rs`):
  `devenv building` while a rebuild is in flight, `devenv ready`/`reloaded`/`failed`/
  `watching N files`/`paused` otherwise.
- Instant no-op (exits immediately, zero delay) when: not inside a zellij pane, `$DEVENV_ROOT` is
  unset, `zellij` isn't on `PATH`, or the last line doesn't currently read "devenv building".
- Otherwise polls every 0.5s, capped at ~60s (120 iterations) so a stuck/slow build can't hang a
  tool call forever.
- Reports what it waited for via the hook's `additionalContext` output field once done (how long,
  and the pane's status line at that point) — see the caveat below for why that's the best
  available signal today, not a live progress indicator.

**Known limitation — no live "waiting for devenv..." indicator yet.** Claude Code's hook schema
supports a `statusMessage` field (a live spinner label shown while a hook runs, configured
alongside `type`/`command` in the generated hook entry) — confirmed via the official hooks
docs — but devenv's own `claude.code.hooks.<name>` Nix option (`hookSubmodule` in
`devenv/src/modules/integrations/claude.nix`) only exposes `enable`/`name`/`hookType`/`matcher`/
`command`, with no passthrough for `statusMessage`. Hook stdout/stderr also isn't shown live to
the user for `PreToolUse` (only surfaced after the hook exits, and even then only on error or via
explicit JSON output fields) — so today the best available signal is the post-hoc
`additionalContext` message this script emits, not a live indicator. Revisit if/when devenv adds
a `statusMessage` option to its hook submodule, or if this repo decides it's worth bypassing
devenv's abstraction for this one hook (e.g. writing the hook entry into `files.".claude/settings.json"`
directly, alongside/overriding what devenv generates) to get the live spinner sooner. Tracked
upstream: [cachix/devenv#3046](https://github.com/cachix/devenv/issues/3046).

## `zellij-wait-for-devenv-start` hook

`wait-for-devenv-start.sh` (`PostToolUse` hook matching `^(Edit|MultiEdit|Write)$`) closes the gap
right after a file write, before devenv's file watcher has necessarily noticed the change yet: if
a fast-firing `Bash` tool call landed in that window, `zellij-wait-for-devenv`'s `PreToolUse` hook
would see a still-stale `devenv ready` and skip its wait entirely, even though a rebuild is about
to start.

- Polls the same pane status line every 0.1s, up to ~1s (10 iterations), waiting only for
  `devenv building` to *appear* — never for the rebuild to *finish* (that's the other hook's job).
- Always proceeds afterward regardless of outcome — a write that doesn't trigger a rebuild (e.g.
  touches a file outside `files.`'s watch set, or produces identical content) is not an error
  here; it just means there's nothing for the next `PreToolUse` hook to wait on.
- Reports via `additionalContext` only when it actually observed the flip to `devenv building`
  (silent no-op otherwise, to avoid noise on every routine edit that doesn't trigger a rebuild).

Confirmed working live during development: an `Edit` to `devenv.nix` (adding this very hook)
triggered the hook, which reported `devenv started rebuilding after 0.2s in pane 16 ... Status
line: ⠧ devenv building for 90ms, changed devenv.nix` — caught well within the ~1s budget.

## Usage in devenv.nix

```nix
kdn.zellij.enable = true;
```

No dependency on `kdn.mcp` or other slots — standalone.

## Future work (not implemented)

Two ideas for widening safe automation without widening the *content-read*/*mutation* allowlist,
noted here rather than built, since neither is needed yet and both need real design work first:

- **A `PermissionRequest` hook dedicated to zellij.** Instead of a static glob allowlist, a hook
  could parse the proposed `zellij`/`zellij action ...` invocation and decide allow/ask/deny based
  on richer logic than a glob can express — e.g. allow `dump-screen -p <id>` automatically only
  when `<id>` is a pane the agent itself created in its own dedicated session (cross-checked
  against a state file recording pane ids the agent has spawned), while still asking for anything
  touching a pane the agent didn't create. This would let "read output from a pane I explicitly
  asked you to run a command in" skip the prompt, without ever silently allowing reads of the
  user's own panes.
- **A safe wrapper script + wildcard allow.** A small script (e.g. `zellij-agent-safe`) that
  accepts a constrained subcommand vocabulary, validates arguments itself (e.g. refuses to target
  a pane/session it doesn't recognize as agent-owned, refuses mutation subcommands entirely), and
  is the *only* thing allow-listed as a wildcard (`Bash(zellij-agent-safe *)`) — pushing the safety
  logic into a reviewable, testable script instead of a glob pattern or an LLM-interpreted hook.
  Would need real design: how the script tracks "panes/sessions the agent owns" persistently
  across invocations, what subset of read-only zellij functionality it exposes, and how it fails
  closed on anything unrecognized.

Either approach should preserve the current policy's invariant — content reads and mutation of
the *user's* session always require an explicit ask — rather than trade it away for convenience.
