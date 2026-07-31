---
type: Task
description: Package a do-nothing `jj-fork-doctor` Python script (wrapped as `jj fork-doctor`) that analyzes fork topology through revset aliases and offers exact remedy commands for the user to confirm and run.
status: todo
authored_by: agent
timestamp: 2026-08-03T17:00:00+02:00
---

# jj-fork-doctor

A do-nothing analyzer for the fork workflow. It reads the current jj graph through the named
revset aliases (`modules/slots/jj/fork/default.nix`), reports the situation, and **offers** exact
commands to reach a satisfactory state. It never mutates. The user copies, confirms, and runs
each command.

## UX contract

- **Do-nothing.** The script only reads (`jj log`, `jj bookmark list`, `jj config get`). It prints
  analysis and suggested commands. It never runs a mutating `jj`/`git` command itself.
- **Offer, then wait.** For each detected situation with a known remedy, print the exact command
  and a preview of what it would move (a `jj log`/`--stat` or a `--dry-run`). Wait for the user.
- **One step at a time, in order.** Follow the ordered checks below. Stop and report if a step
  needs a human decision (undescribed work, conflicts, divergence).

## Hard constraints

- **Suggestions MUST use revset aliases only — never raw change ids.** Every offered command
  refers to named aliases (`tree-merge`, `upstream-incoming-tip`, `upstream-safe`, …), not
  `xtuzqnyn`-style ids. When the current alias set cannot express a needed suggestion, the script
  **must say so explicitly** ("alias set insufficient for X — add alias Y") instead of falling
  back to raw ids.
- **Never touch interleaved fork-chain commits.** When it extracts upstream-safe changes from
  between fork-chain commits, the offered command must move only the upstream-safe changes and
  leave fork-chain commits in place.
- **Never push.** The user reviews and pushes. The doctor may offer `jj sync-remotes`, which
  itself prompts before pushing.

## Ordered checks

1. **Committed but not pushed.** Are there described local changes not on any remote?
   Alias basis: `~pushed & ~description("")`. Report the set.
2. **Mutable upstream→fork merge.** Is there a rebaseable merge?
   - `tree-merge` present and `merge-frozen` empty → reusable. Report it.
   - No local merge, or `merge-frozen` non-empty → **offer to create one** (use case 5:
     `jj new 'fork-tip' 'upstream-incoming-tip' -m '...'`).
3. **Upstream-safe changes between the merge and `@`.** `upstream-safe` non-empty →
   **offer to push them onto the upstream chain**. The command must extract only the
   upstream-safe changes and leave any interleaved fork-chain commits in place.
4. **Fetch.** Offer `jj git fetch` (or the fetch half of `sync-upstream`).
5. **Upstream changes not in the upstream chain.** `upstream-incoming` non-empty →
   **offer to rebase** (use case 4: `jj rebase -s 'roots(upstream-local)' -d 'upstream-incoming-tip'`,
   then re-point bookmarks).
6. **Anything to push.** Commits ahead of `main@<fork>` or `upstream@<upstream>` →
   **offer `jj sync-remotes`**.

## Guard conditions (analyze-only, no offers)

- `@` or an ancestor has conflicts or divergent changes → report, do not offer.
- Undescribed `@` (work in progress) → report it blocks a clean picture. Do not offer to describe
  it; that needs a human commit message.

## Alias sufficiency — gaps found (verify and close before build)

The current alias set covers steps 2, 4, 5. Three gaps remain:

- **Step 1 (unpushed):** no named alias. Add e.g. `unpushed = "~pushed & ~description(\"\")"`.
- **Step 3 (extract upstream-safe from between fork commits):** no alias for "upstream-safe not
  already on the upstream chain", and the extraction is per-commit. This **conflicts with the
  alias-only rule** — you cannot name individual change ids. Design decision needed: either add
  aliases plus a `jj rebase -r '<revset>'`-style command that moves a whole revset at once, or
  document a narrow exception. Resolve this first — it is the hardest step.
- **Step 6 (to-push):** `sync-remotes`/`sync-upstream` compute `main@<remote>..tip` inline with
  raw remote refs. Add `to-push-fork` / `to-push-upstream` aliases so the doctor can report the
  push sets by name.

Also useful: a `bookmarks-stale` check (is `main`/`upstream` off its expected target?) — the most
common real-world mess. Consider an alias or a direct bookmark-vs-alias comparison.

## Packaging

- Scaffold with `nix run .#init-py-script -- jj-fork-doctor` (see
  [.agents/rules/packaging-python.md](../../.agents/rules/packaging-python.md)).
- Binary name `jj-fork-doctor`; module `jj_fork_doctor.cli`; `prog="jj-fork-doctor"`.
- Wrap as `jj fork-doctor` — add `aliases.fork-doctor` in `modules/slots/jj/fork/default.nix`,
  next to `fork-help`, pointing at the packaged binary
  (`util exec -- ${pkgs.kdn.jj-fork-doctor}/bin/jj-fork-doctor`).
- `runtimeDeps = [ pkgs.jujutsu ]` so `jj` is on PATH.
- The script reads alias values with `jj config get` or resolves sets with `jj log -r '<alias>'`,
  so it stays in sync with the slot definitions and needs no duplicated revset strings.

## Relation to the pytest suite task

This is a strong driver for [jj-fork-revset-pytest-suite.md](jj-fork-revset-pytest-suite.md). The
doctor is deterministic analysis over a known topology, so the same three-repo fixture
(local/upstream/fork) can assert both the alias results and the doctor's reported situation +
suggested commands. Build the fixture once; use it for both. Consider building the doctor and the
suite together.

## Reference rebase commands

Two rebase forms cover the two directions of movement. Note both for the implementer.

- **Step 3 — push upstream-safe changes down below the merge, onto the upstream chain:**
  ```bash
  jj rebase -r 'upstream-safe' --insert-after 'upstream-tip'
  ```
  `-r` moves only those revisions, not their descendants. `--insert-after` (`-A`) places them on
  top of `upstream-tip` and re-parents the descendants (the merge, then `@`) onto the moved chain.
  The merge keeps its fork parent, so it stays a clean 2-way merge. Follow with
  `jj bookmark set upstream -r 'upstream-tip'` and `jj bookmark set main -r 'tree-merge'`.

  > **Needs validation — interleaved fork-chain commits.** This one command works only when the
  > upstream-safe changes are contiguous (no fork-chain commit sits between them), as confirmed
  > on 2026-08-03 when `fork-leaked` was empty. When fork commits ARE interleaved, `upstream-safe`
  > is a non-contiguous revset. It is unverified whether `jj rebase -r '<revset>'` can lift a
  > non-contiguous subset and leave the fork commits in place. Test this empirically against the
  > MVP pytest suite ([jj-fork-revset-pytest-suite.md](jj-fork-revset-pytest-suite.md)) before the
  > doctor offers this command for the interleaved case.

- **Step 5 — pull new upstream in, rebase the pre-merge upstream chain onto the fetched tip:**
  ```bash
  jj rebase -s 'roots(upstream-local)' -d 'upstream-incoming-tip'
  ```
  `-s` moves the chain root and all its descendants (the merge, `to-rebase`, `@`) as one. The
  merge keeps its fork parent. See use case 4 in
  [../jujutsu-vcs.fork.md](../jujutsu-vcs.fork.md) for the full sequence and the warning against
  rebasing `tree-merge` directly.

- **No rebase preview.** `jj rebase` has no `--dry-run`. The doctor cannot show a real preview for
  a rebase offer. It can show the source/destination sets by alias and rely on the user running
  `jj undo` if the shape is wrong.

## Open questions

- Step 3 extraction semantics: verify whether the single `jj rebase -r 'upstream-safe' -A ...`
  command holds for interleaved fork-chain commits (see the validation note above). Prototype on
  a fixture before you wire the offer.
- Should the doctor offer to fix stale bookmarks as a distinct early step (before step 2)?
- Output format: plain text, or a structured summary the pytest suite can assert against?
