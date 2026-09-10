---
type: Task
description: Make zellij-llm clearer and easier to use — reduce the boilerplate and confusing steps an agent/user hits when driving long-running commands in a dedicated zellij session.
status: done
authored_by: agent
timestamp: 2026-07-31T12:30:00+02:00
---

# Make zellij-llm clearer to use

Driving a long-running command through `zellij-llm` currently takes more ceremony than it
should, and the friction points aren't obvious until you hit them. Reduce that friction and
document the happy path.

## Friction observed 2026-07-31 (while setting up the rosetta-builder darwin build)

1. **Two-step name dance.** You must run `kdn-slug names --type session` first, capture the
   output, then pass it to every `zellij-llm` call via `--session`. Easy to forget; verbose.
   (Being fixed structurally by [[zellij-llm-derive-names-from-kdn-slug]] — this task is the
   docs/UX half.)
2. **Socket-path length blows up non-obviously.** The default derived session name exceeds
   zellij's 103-byte IPC socket-path limit and only fails at `spawn` time with a cryptic
   `the IPC socket path is too long` error — not at name-generation time. Users don't know they
   need `--max-len` / a shorter name until it explodes.
3. **`--help` discoverability.** It should be obvious from `zellij-llm --help` and each
   subcommand's `--help` what the minimal invocation is (ideally just `zellij-llm spawn --pane
   '...'` once name derivation lands).

## Convention: feed commands via HEREDOC, not `echo`

When feeding a command into `zellij-llm` on stdin, **always use a HEREDOC**, e.g.:

```bash
zellij-llm spawn --pane 'build' <<'EOF'
nix run ".#darwin-rebuild" -- build
EOF
```

rather than `echo '...' | zellij-llm spawn ...`. The HEREDOC renders far more readably in the
Claude Code permission prompt (the command stands alone as its own block instead of being
mangled into an `echo ... | ...` pipeline), and it handles multi-line command scripts cleanly.
Document this in both the tool help and the zellij skill doc as the recommended invocation
style.

## Behavior: spawn must persist session + panes by default

`zellij-llm spawn` (and `spawn-and-watch`) must **keep the session and its panes alive after the
fed command finishes** — so the user can attach afterwards and review output, re-run, or inspect
scrollback. Do **not** tear down the session or close the pane when the command exits by default.

Only exit/clean up if the caller explicitly opts in via a flag (e.g. `--ephemeral` /
`--close-on-exit`). Default = persistent; ephemeral = opt-in.

Note: `zellij-llm` already runs fed commands under `bash -xeEuo pipefail`, so `-x` echoes each
command as it runs into the pane. Keep that behavior (and surface it in `peek`/watch output) so
the user can see exactly which command to re-run — the trace line (`+ nix run ...`) is what makes
a persisted pane useful for re-running after the fact.

**Caveat — secrets in the `-x` trace.** `-x` echoes the fully-expanded command, so any secret
passed as a literal CLI arg or an inline env assignment (`FOO=$TOKEN cmd`, `--password abc`)
leaks into the pane scrollback (and any `peek`/watch output). When a command handles secrets:
feed them via a file / env var referenced by name (not value), or wrap the sensitive step in
`{ set +x; ...; set -x; } 2>/dev/null`. Document this so callers don't accidentally splash
tokens into a persisted pane.

## Convention: pane names / tags are short slugs

Pane `--pane` values and any tags must be **short kebab-case slugs** (e.g. `darwin-build`,
`flake-update`), not full sentences like `build: darwin-rebuild rosetta 2`. Slugs read cleanly
in `list`/`peek` output and in the pane title bar, and stay attributable. Document this and
consider validating/normalizing overly long or sentence-like names.

## Don't `sleep` then `peek` — provide a wait-for-exit / interval watch

Observed anti-pattern 2026-07-31: an agent repeatedly ran `sleep N; zellij-llm peek ...` to poll
a long build. That's counterproductive — it either wastes time or peeks too early at a
half-finished log.

Add first-class waiting/watching affordances rather than leaving agents to `sleep`+`peek`:

- **`watch` subcommand** — attach to an already-spawned pane and follow it (stream or heartbeat)
  until its command exits, same output modes as `spawn-and-watch`. For observing a pane you
  spawned earlier (or a still-running one) without re-spawning.
- **`wait` subcommand** — block until a given pane's command exits (keying off the `EXIT:<code>`
  marker `spawn-and-watch` already emits) and return that exit code, with no output streaming.
  Lets an agent `spawn` then `wait` without polling.
- **`--wait` suffix/flag where appropriate** — e.g. `spawn --wait` == today's `spawn-and-watch`;
  offer `--wait` on any subcommand where "do it, then block until done" is a natural mode, so
  the waiting behavior is a consistent modifier rather than a separate memorized command name.
- `spawn-and-watch --mode heartbeat --interval N` already exists — keep it, and make waiting the
  **documented default** for long-running commands instead of manual `sleep`+`peek` loops.
- `peek` could optionally take a poll `--interval` / `--until-exit` so a single call streams
  until completion rather than requiring external sleeps.

## What to do

- Tighten `zellij-llm --help` / subcommand help so the **minimal** invocation is front and
  center, and the name-derivation + override behavior is documented in one place.
- Surface the socket-length constraint proactively: validate the derived/passed session name
  against zellij's limit and emit a clear, actionable error (or auto-shorten) rather than
  letting zellij fail deep in `spawn`.
- Update the zellij skill doc (`.claude/skills/zellij/SKILL.md` or its source under
  `modules/slots/zellij/`) so the documented pattern matches the simplified tool — drop the
  manual `kdn-slug names` pre-step from the happy path once derivation lands.

## Acceptance

- A newcomer can copy one `zellij-llm spawn --pane '...'` line from the docs and it works.
- The socket-length failure mode is caught early with a helpful message.
- Skill doc and tool help agree with each other and with actual behavior.

## Pointers

- `packages/llm/zellij-llm/zellij-llm.sh`, `packages/llm/zellij-llm/default.nix`
- `modules/slots/zellij/default.nix` (skill install), `.claude/skills/zellij/SKILL.md`
- Related: [[zellij-llm-derive-names-from-kdn-slug]]
