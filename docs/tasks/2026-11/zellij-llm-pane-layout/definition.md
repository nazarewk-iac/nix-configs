---
type: Task
description: Make zellij-llm spawn its command into a clean, stacked session instead of resurrecting stale panes, and make the Pi harness resume the previous session instead of starting fresh each time.
status: open
authored_by: agent
timestamp: 2026-11-02T19:47:16+01:00
---

# Clean stacked panes for zellij-llm, and a resuming Pi harness

## Problem 1 — every launch adds panes to a stale session

Observed on 2026-11-02 with `zellij-llm start --session llm:nix-configs:smartpi --pane pi -- ...`:

- The first launch creates the session and one pane; fine.
- After the session has exited (the command ended, the pane dropped to a shell), a **second**
  `start` on the same `--session` attaches to the resurrected session, which brings back the
  old pane(s), then adds a new pane. A third launch adds a third. After three launches the
  session holds three `pi`-titled panes, only the newest live.
- The layout is a **split** (side by side), not stacked, in practice. The skill doc says
  panes are stacked; the actual `new-pane` path does not preserve a stack when the session is
  resurrected.

Cause (read in `packages/llm/zellij-llm/zellij-llm.sh`): `_ensure_session` calls
`zellij attach --create-background <session>`. When the session is **not running** but a
resurrectable snapshot exists, zellij **resurrects** the old layout (all old panes) and then
`action new-pane` appends the new one. `_stack_with_existing` then stacks the union, so the
stale panes come back as siblings.

## Problem 2 — the Pi harness always starts a fresh session

The harness is launched with a fresh `pi ... "<brief>"` prompt on every relaunch. Pi **does
save** the session continuously (`~/.pi/agent/sessions/<cwd-slug>/<iso>_<uuid>.jsonl`), and
`pi --continue` / `pi --resume` / `pi --session <id>` exist. But our launch command never
passes one, so every relaunch is a brand-new session and none of the earlier analysis is
carried over — the orchestration "resumes the work" only because the brief re-describes it.
That wastes the prior run's context (it re-reads the 66 transcript chunks from scratch).

## Goal

**Part A — zellij-llm session hygiene.** `start` (and `spawn`) should put the command in a
session with:

1. **Only the requested pane(s)** — no stale resurrected panes. Options to weigh:
   - `kill-session` first when the session exists but has no live command, then create
     clean; or
   - create a fresh named session per run (already the `kdn-slug` default with a run id);
     or
   - `zellij delete-session --force` the resurrectable snapshot before `attach`.
     Do **not** silently kill a session that still has a live process.
2. **Stacked panes** as the default layout, with the command in the top (most recent) pane.
   Verify after attach, not just after create: the resurrect path is where the stack is lost.
3. Ideally a single `worker` tab; **one empty tab beside `worker` is acceptable**. No extra
   tabs per launch.

**Part B — the Pi harness resumes.** The launch wrapper (in `zellij-llm start ... -- pi ...`
and/or a small script in the repo) should:

- Reuse the previous session when one exists for this repo: `pi --continue` (last) or
  `pi --resume` (pick) or `pi --session <id>`, instead of a bare fresh `pi`.
- Keep the brief as the **new user turn** on the resumed session, so the model sees its own
  earlier analysis in context, not a cold description.
- Leave a clean way to force a fresh run (`--fresh`-style flag), because a corrupted or
  unrelated last session must not hijack a new task.

## Investigation notes

- `packages/llm/zellij-llm/zellij-llm.sh`: `_ensure_session` (around line 516) is the
  resurrection trigger; `_run_start` (around line 229) calls `new-pane` then
  `_stack_with_existing`.
- `zellij attach --create-background` resurrects; a plain `zellij attach <name>` to a dead
  session likewise offers resurrection. Confirm whether `--create-background` on a _dead_
  session resurrects silently (the observed behaviour) or only on an explicit attach.
- The zellij skill (`.agents/skills/zellij/SKILL.md`) documents "spawn folds the pane into the
  stack"; that is true only for a live session, so the skill needs a note about the
  resurrect path.
- Pi resume: `pi --continue`, `pi --resume`, `pi --session <path|id>`, `--session-id <id>`;
  sessions live under `~/.pi/agent/sessions/<slugified-cwd>/`.

## Acceptance

- Launching the harness twice in a row into the same session leaves **one live command pane**
  plus at most one empty tab; no stale duplicate panes.
- The panes are **stacked**, and the command pane is the visible one.
- The second launch shows the first session's history (the model can refer to what it did
  before) — demonstrated by asking it to recall a fact from the prior run.
- `--fresh` (or equivalent) still starts a clean session.
