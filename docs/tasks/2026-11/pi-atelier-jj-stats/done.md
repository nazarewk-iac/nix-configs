---
title: jj stats and sub-agent performance stats — solution
type: Reference
description: What shipped in the pi-atelier fork, the exact code added, and how to verify it.
timestamp: 2026-11-02T20:50:00+01:00
---

# Solution

Forked `michaelmjhhhh/pi-atelier` into `nazarewk-iac/pi-atelier` and implemented both asks on
branch `nazarewk-iac/jj-and-stats` (rev `d7bf77f`). The repo vendors that rev through
`packages/pi-coding-agent-extensions/default.nix` (`pi-atelier` → `version = "0.18.0+jjstats"`).

## jj, preferred over git

- New `src/workspace-pulse.jj.ts` returns the **same `WorkspacePulseInspection`** shape as the
  Git inspector, so the sidebar, footer, and refresh machinery are shared unchanged.
- `src/state.ts` probes `jj root` first; when the directory is inside a jj repo it uses the jj
  backend, otherwise it falls back to the Git inspector. (`inspectWorkspace` dependency still
  overrides both.)
- Every jj read uses `--ignore-working-copy`, so a status poll never snapshots the working copy.
- `WorkspacePulseData` gained `vcs`, `jjChangeId`, `jjBookmarks`; the workspace panel shows the
  change id and up to three bookmarks when `vcs === "jj"`.
- Fields: `trackedFiles` (files in `@` vs `@-`), `linesAdded`/`linesRemoved` (`jj diff --stat -r @`),
  `conflicts` (`jj log -r @ -T conflict`). "Untracked" does not exist in jj; a new file counts as
  changed.

Verified live on this repo: change id `mpulkxpqskww`, clean snapshot; and `not-repo` outside jj.

## STATS panel

- New `src/subagent-speed-history.ts` reads the same per-child `events.jsonl` the cost reader
  uses and projects, per reply, `output / (durationMs/1000)` — a whole-reply average tok/s.
  `seriesAverage()` gives the mean over a run's replies.
- `SubagentUsageSnapshot` gained `speedHistory`; the sidebar renders a new **STATS** panel beside
  SUBAGENTS: for a closed run the mean tok/s, for a live one its latest reply's tok/s, labelled
  as a whole-reply average.
- TTFT history is not available (the child stream records no request-start marker); TTFT stays
  live-only for the parent, which already works in `run-activity.ts`.

## Verification

- `npx vitest run`: **504 pass** (27 files), including new `tests/workspace-pulse-jj.test.ts`
  and `tests/subagent-speed-history.test.ts`.
- `tsc --noEmit` clean; `biome check src tests` clean.
- Extension builds from the fork and Pi loads it without error.

## Follow-ups

- Upstream the jj backend and the STATS panel as a PR if the author wants them.
- If a future Pi build records a per-reply request-start time, add TTFT history from the same
  reader (the `at`/`durationMs` fields are already there).
