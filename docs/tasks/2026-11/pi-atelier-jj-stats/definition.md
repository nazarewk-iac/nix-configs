---
type: Task
description: Extend the vendored pi-atelier status rail with Jujutsu (jj) stats and with sub-agent performance stats (live and historical TTFT and tok/s). Records what exists today, what it costs to add, and the caveats.
status: done
authored_by: agent
timestamp: 2026-11-02T20:16:15+01:00
---

# jj stats and sub-agent performance stats in pi-atelier

> **Done.** Implemented in the fork `nazarewk-iac/pi-atelier` (branch
> `nazarewk-iac/jj-and-stats`, rev `d7bf77f`), vendored by
> `packages/pi-coding-agent-extensions/default.nix`. See [done.md](done.md).

pi-atelier is vendored at `packages/pi-coding-agent-extensions/default.nix` (rev `93025f2`,
v0.18.0). Two extensions are asked for:

1. A **Jujutsu** view, alongside or instead of the Git view.
2. **Sub-agent performance stats** — time to first token (TTFT) and tokens/second —
   live and historical.

## Part 1 — the Git view today, and a jj equivalent

### How big the Git feature is

All Git logic is **one module, `src/workspace-pulse.ts` (345 lines)**. It runs three Git
commands through an injected `exec(command, args, opts)`, each with a 2 s timeout:

1. `git rev-parse --is-inside-work-tree --show-toplevel` — repo detection and root.
2. `git status --porcelain=v2 -z --branch --untracked-files=all` — branch, tracked,
   untracked, conflicts, submodules (`parseStatus`).
3. `git rev-parse --verify HEAD^{tree}` then `git diff --numstat -z --find-renames` — lines
   added/removed/binary (`parseNumstat`); an unborn branch diffs against `EMPTY_TREE_HASH`.

It returns `{kind:"available", root, relativeCwd, branch, snapshot}`, where `snapshot` is
`trackedFiles, untrackedFiles, linesAdded, linesRemoved, binaryFiles, submodules, conflicts`;
or `{kind:"not-repo"}` / `{kind:"unavailable"}`. `createWorkspacePulseRefresh` debounces and
serialises the inspection, aborts in flight, and disables itself for an untrusted project.

Rendering and wiring are thin: `src/state.ts` (~10 lines to bind `exec: this.#pi.exec` and
expose state), `src/sidebar.ts` ~50 lines (`workspacePulseRows`), `src/footer.ts` ~15 lines
(a one-line branch segment), `src/display.ts` (a `git` footer segment).

**Verdict:** the Git feature is small and cleanly isolated — one 345-line module is the work;
render + wiring is ~80–120 lines. The seam is a single `inspect*` returning one of three
shapes, so a parallel backend reuses the whole renderer and refresh machinery untouched.

### What a jj view takes

jj is not Git to the tool, but it exposes its own porcelain and a Git interface. **Option A
(replace the backend, recommended):** keep the snapshot shape, write
`src/workspace-pulse.jj.ts` that fills the same fields from jj:

| Field          | jj source                                                                |
| -------------- | ------------------------------------------------------------------------ |
| root           | `jj root`                                                                |
| branch         | `jj log -r @ --no-graph -T 'bookmarks'` (bookmarks on `@`; may be empty) |
| trackedFiles   | `jj diff --summary -r @` line count, or `jj diff --stat -r @`            |
| lines +/−      | `jj diff -r @ --git` parsed with the existing numstat parser             |
| conflicts      | `jj resolve --list` (empty = none), or `jj log -r @ -T 'conflict'`       |
| current change | `jj log -r @ --no-graph -T 'change_id.short()'` — **no Git analogue**    |
| untracked      | has no jj meaning (see caveat) — map to "Added"/new files or drop        |
| submodules     | n/a — drop the row                                                       |

Cost: **~200–300 lines** for the jj inspector + parser (jj templates parse more cleanly than
porcelain-v2, but the vocabulary differs), a small snapshot extension for the jj-only fields
(`changeId`, `bookmarks`), and a probe order in `inspectWorkspace()` (`.jj/` before `.git/`).

**Option B (parallel panel):** leave Git and add a "Jj" block shown for jj repos — reuses
the refresh machinery, ~150–250 lines for the module + ~40 to render a second block.

Either is additive; a fork keeps the diff small.

### jj caveats (research first)

1. jj colocated repos have both `.jj/` and `.git/`; decide detect-and-prefer vs show-both.
2. "Untracked" has no jj meaning — jj auto-tracks into `@`.
3. "Modified files" means files in `@` vs `@-` (`jj diff -r @`), **not** uncommitted-vs-HEAD —
   the label must say so.
4. **Cost per refresh.** A read may snapshot the working copy (a write op), so a frequent
   poll can cause a `jj st` write storm; the 2 s timeout may be tight. Investigate
   `jj --ignore-working-copy` for the read-only case — likely the right poll default.
5. Prefer an upstream-PR-able `WorkspacePulseExecutor` seam over a wholesale fork.

## Part 2 — sub-agent performance stats (TTFT and tok/s)

### What exists today

- **Live performance for the PARENT session** is implemented: `src/run-activity.ts` tracks an
  in-flight response (`requestedAt`, `firstTokenAt`, `firstTokens`, `latestTokens`) and
  derives `performance.ttftMs` (time to the first observed chunk) and `performance.tokensPerSecond`
  (estimated from observed deltas). `src/sidebar.ts::responsePerformanceRows` renders
  "First token" and "Output speed N tok/s". The footer shows TTFT (`src/footer.ts`).
- **Sub-agent accounting is cost-only.** `src/subagent-usage.ts` + `subagent-cost-history.ts`
  read each child run's `events.jsonl` and project **only** `message.usage.cost.total` into
  a cost curve (`SubagentCostSeries`). Their comment is explicit: "Project accounting fields
  only. No content, prompt or tool arguments leave this reader."
- So today you get **per-child cost over time**, and **TTFT/tok/s only for the parent's
  current (live) response** — nothing historical, and nothing per sub-agent.

### What the child data already contains

The child `events.jsonl` lines are `type:"message_end"`, `subagentSource:"child"`,
`subagentRunId`, `subagentStepIndex`, `subagentAgent`, `observedAt`, and `message` (role
`assistant` with `usage`). Pi's assistant `usage` carries `input`, `output`, `cacheRead`,
`cacheWrite`, `reasoning`, `totalTokens`, `cost`, and the message carries `timestamp` and
`durationMs`. That is enough to compute, **per reply**:

- **TTFT**: not directly recorded per reply. It can be approximated only if the event stream
  also carries a start marker (request-sent) for the same reply; otherwise it is
  unavailable for history. Verify what the child stream records before promising it.
- **tok/s**: `output / (durationMs/1000)` — a per-reply average decode rate, available from
  the recorded `durationMs` and `output` tokens. This is a whole-reply average, not the live
  sliding estimate the parent uses.

### What implementing it takes

**Live, per sub-agent (easier):** the parent can observe each child's stream as it arrives,
the way `run-activity.ts` already does for its own response. Add a small per-child tracker
(mirroring `TrackerState.response`) keyed by `subagentStepIndex`, fed by the same child
events the cost reader already sees. **~150–250 lines**, no new file format.

**Historical, per sub-agent (more work):** extend `subagent-cost-history.ts` into a
`subagent-stats-history.ts` that projects `output`, `durationMs`, and `timestamp` per
`message_end` into points, then render a second series beside the cost curve. **~200–300
lines**: a new point type, the reader change (it already streams the lines), and a renderer.
TTFT history is only possible if the stream records a request-start time; if not, show tok/s
history and leave TTFT live-only.

### Caveats

1. **tok/s is a whole-reply average** from `durationMs`, so it includes prefill and queue
   time — it under-reports decode speed on a loaded CPU model. Label it "avg tok/s".
2. **TTFT needs a request-sent timestamp.** Confirm the child event stream has one; if it
   does not, TTFT is live-only (parent) and cannot be historical.
3. **The fleet is CPU-heavy.** tok/s for the CPU frontier is ~2–10; the number will look
   bad but is honest, and it is exactly the signal the operator wants to see.
4. **Privacy.** The existing readers are deliberately content-free. Performance points are
   numbers only, so they fit the same rule — keep prompts/output out.
5. **A fork, not upstream.** Vendored; prefer a small patch, and upstream the generic
   `WorkspacePulseExecutor`/stats seam if it proves useful.

## Deliverables

- Verified numbers for the review: the Git module size and the sub-agent cost-only scope
  (both confirmed by reading the vendored tree).
- A design note choosing A vs B for jj, and a decision on historical TTFT (possible or not).
- A prototype jj inspector behind a `.jj/` probe, proved on this repo (jj).
- A sub-agent performance tracker proving, for at least one run: per-child avg tok/s live,
  and (if the stream allows) a history series rendered beside the cost curve.

## Acceptance

- On a jj repo the rail shows jj stats (current change id, modified-file count, +/−,
  conflicts, bookmarks); on a plain Git repo it shows the Git stats.
- For a run with sub-agents, the sidebar shows per-child output tok/s (live, and historical
  if the event stream carries the timing).
- `jj op log` (or `.jj/working_copy` mtime) shows no write storm during a poll — proof of
  `--ignore-working-copy` or an equivalent guard.
- The parent's own TTFT/tok/s continues to work unchanged.
