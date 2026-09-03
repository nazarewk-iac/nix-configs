---
type: Task
authored_by: agent
description: Solution record for push-to-branch-or-fork — the verified golden path and the canonical harness-extension example.
timestamp: 2026-09-04T00:00:00+02:00
---

# Push a change to a branch or fork — solution

## Root cause analysis (the gap)

The docs, the skill, and the harness covered how to *place* content in the fork
topology, but not the plain workflow: you have a local change and you want to
**push it to a branch or fork** (the shared `main`/`master`, a feature branch, or
a second fork remote) after a fresh fetch. The harness also had no single worked
example that teaches a reader how to **extend** it.

## Solution

- `checks/jj-experiments/test_push.py` — 9 verified tests: anonymous PR branch,
  named tracked branch, fast-forward, behind (Approach B whole-stack and tip),
  insert refused (trunk/untracked), insert on a tracked feature branch, divergent,
  and a second fork remote.
- `checks/jj-experiments/test_push.md` — the golden-path walkthrough plus an
  "extend the harness" teaching layer.
- `checks/jj-experiments/topologies.py` — the shared scaffolding
  `build_push_base` / `advance_remote` / `push_feature`, extracted in a follow-up
  to show the "start inline, then extract when it repeats" method.
- `docs/jujutsu-vcs.md` — a "Push the branch to a remote" golden path and an index
  row; `README.md`, the `jujutsu-vcs` skill, and the `jj-expert` agent point to
  `test_push` as the canonical extension example.

Golden path:

```sh
jj git fetch --remote=<remote>
jj rebase -b @ -d <branch>@<remote>       # skip if already ahead
jj bookmark set <branch> -r <your-rev>
jj git push --remote=<remote> -b <branch>
```

Verified jj-0.44 facts that shaped it:

- No `--allow-new`; a new named bookmark pushes directly and starts tracking.
  Anonymous PR branch: `jj git push -c <rev>` → `push-<changeid>`.
- **Approach B** (rebase your work onto the incoming) is the path for the shared/
  primary branch — the incoming trunk is immutable. **Approach A** (insert the
  incoming under your work) is refused for the trunk or an untracked bookmark, but
  works on a tracked, non-trunk feature branch (track → insert → push).
- `jj git push` is force-with-lease: a **pre-fetch** push of a moved branch is
  **rejected** ("stale info"); only a **post-fetch** bare push clobbers sideways.
  There is no fast-forward-only flag. Safe default: push a feature/PR branch,
  never `bookmark set main` + push.

## Verification steps

- `pytest checks/jj-experiments/` → **92 passed** (9 new); each recipe asserts the
  real post-state (remote bookmark, tracking, divergence by commit id, returncode).
- Independent phase-3 review: clean across proof-validity, doc/test/design
  consistency, extraction quality, and hygiene (only 3 nits, all fixed).
- `fork-leaked` and `to-rebase` empty; no employer terms; nothing pushed.

## Follow-up notes

- Upstream-chain commits: `pmllouou` (design), `ozqnynxv` (implement + folded
  Q1/Q2 feedback), `mnuquqyr` (extract topology), `xkozvvnr` (link as the shining
  example).
- `test_divergent_rebase_resolves` overlaps `test_behind_whole_stack_rebase_b` but
  adds the disjoint-files/no-conflict angle; kept as acceptable coverage.
