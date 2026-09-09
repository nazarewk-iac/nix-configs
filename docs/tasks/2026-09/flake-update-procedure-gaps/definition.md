---
type: Task
description: Repair the flake update procedure — add a fetch and a reconcile step, a start-state branch, and a completion check.
status: open
authored_by: agent
timestamp: 2026-09-09T00:00:00+02:00
---

# Repair the flake update procedure

Findings and the corrected procedure: [flake-update-procedure-gaps.research.md](research.md).

## Goal

Make one fork flake update correct and repeatable from any start state. The procedure must
tell the operator to fetch first, to reconcile the remote tips, to name the start state,
and to prove the run is complete before the hand-off.

## Defects

Three defects were measured before this task. All three are confirmed.

- **D1 — no fetch, no reconcile.** No update doc and no rule mentions a fetch. The only
  fetch sits inside the `sync-upstream` alias and runs at push time
  (`modules/slots/jj/fork/default.nix:184`). The last fetch in this repo ran 2026-09-08
  10:29; the current update commit was made 2026-09-09. So every placement decision read
  remote-tracking refs about 24 hours old.
- **D2 — the documented start state is not the usual state.**
  `docs/flake-update.fork.md:83,120` assume `@` is empty with two parents. In practice `@`
  sits on a linear stack. All six current local commits are `fork`-tagged, so
  `upstream-tip` resolves **below** the tree merge and the documented step 3 command
  grafts the public commit to the wrong parent.
- **D3 — no completion check.** Nothing states that a finished update leaves two commits,
  one per chain. Today exactly one exists, and the public chain's two lock files are
  byte-identical to `refs/remotes/kdn/main`.

18 more defects (O1–O18) and 12 skill divergences (S1–S12) are listed in the research
file. The worst three:

1. **O18a** — `modules/slots/jj/pre-push.sh:65-67` gates the sensitive-path check to the
   **private** remote, while `modules/slots/jj/default.nix:54` documents the opposite. The
   public push gets no file check.
2. **O12** — the insert command needs `fork-tip` to be a mutable merge. No doc states the
   precondition, so the command breaks the topology in the usual start state.
3. **O10** — no doc checks that the `devenv.lock` strip list is not empty. An empty list
   makes the transform a no-op and every fork node stays in the public `devenv.lock`.

## Work items

### Docs

- [ ] `docs/flake-update.fork.md` — add **step 0**: `jj git fetch --all-remotes`, then the
      reconcile table (four outcomes: nothing moved, public tip moved, fork tip moved,
      both moved). State that a rebase is required in one case only.
- [ ] `docs/flake-update.fork.md` — add **step 1**: the start-state table with the five
      states and the first step for each. Mark states (ii), (iii) and (iv) as "work first".
- [ ] `docs/flake-update.fork.md` — add the case (iv) correction sequence (reorder before
      the update, oldest safe commit first).
- [ ] `docs/flake-update.fork.md:95,159` — add the mutable-merge guard before the insert
      command (O12).
- [ ] `docs/flake-update.fork.md:99-106,185-192` — drop the `^brew-tap--` prefix filter;
      derive the strip list from the root-inputs diff (O9).
- [ ] `docs/flake-update.fork.md:185-193` — assert the strip list is not empty (O10).
- [ ] `docs/flake-update.fork.md:82-112` — add the patch-file move to the quick summary
      (O11).
- [ ] `docs/flake-update.fork.md:209-215` — replace "Verify the topology" with the
      completion check (D3, O13).
- [ ] `docs/flake-update.fork.md:227` — use `"$f"`, not the hardcoded `flake.lock` (O8).
- [ ] `docs/flake-update.fork.md:9-11` — correct the claim about which file the slot
      installs (O7).
- [ ] `docs/flake-update.fork.md` — add `jj fork-audit -q --color=never 'upstream-tip'` to
      the verify step (O16), and a warning that the two pushes are not atomic and the
      public push runs first (O17).
- [ ] `docs/flake-update.fork.md:399-408` — state that the NixOS build of `upstream-tip`
      gates the public push, and the Darwin build of `fork-tip` gates the private push
      (O15).
- [ ] `docs/flake-update.md:22-30` — add the guard: this procedure applies when
      `kdn.jj.fork.enable = false` (O1, O2).
- [ ] `docs/flake-update.md:114` — replace `upstream@<fork-remote>` with
      `main@<public-remote>` (O3).
- [ ] `docs/flake-update.md:66-71` — point the patch branch at `docs/flake-patches.md` and
      the `flake-patches` skill; keep one branch per failure cause (O14).

### Agent rules

- [ ] `.agents/rules/flake-update.fork.md` — add the fetch line, the start-state check,
      and the completion check to the quick sequence. Add the mutable-merge guard.
- [ ] `.agents/rules/flake-update.fork.md:28-34` — align the graph drawing with the doc
      (S7).
- [ ] `.agents/rules/flake-update.md:9,11,13` — correct the three broken links (O4).
- [ ] `.agents/rules/flake-update.md:17-27` — add the fork guard (O2), add
      `devenv update` (S12), and replace `upstream@<fork-remote>` (O3).

### Skills

- [ ] `.agents/skills/flake-update-fork/SKILL.md:8` — correct the link depth (O6).
- [ ] `.agents/skills/flake-update-fork/SKILL.md` — add step 0 (fetch + reconcile), the
      start-state gate, the mutable-merge guard and the completion check. Align the step
      numbers with the doc (S6).
- [ ] `.agents/skills/flake-update-fork/SKILL.md:66-67` — align the graph drawing (S7).
- [ ] `.agents/skills/flake-update/SKILL.md:8-10` — correct the three broken links (O5).
- [ ] `.agents/skills/flake-update/SKILL.md:20-21` — add the fork guard (S1).
- [ ] `.agents/skills/flake-update/SKILL.md:42` — replace `upstream@<fork-remote>` (S3).
- [ ] `.agents/skills/flake-update/SKILL.md:9` — name the `flake-update-fork` skill, not
      only the doc (S11).
- [ ] Both skills — decide how a consumer repo reaches the full docs. Every `docs/…` link
      is dead after the slot installs the skill (S10). Either inline the essentials, or
      link to a stable URL.

### New artifacts

- [ ] Add the completion check as a script, for example
      `hack/flake-update-complete.sh`. Ten assertions, exit 1 on any FAIL. The text is in
      the research file § 8.
- [ ] Add `fork-incoming = @..main@<fork-remote>` and
      `fork-incoming-tip = main@<fork-remote>` to `modules/slots/jj/fork/default.nix`, as
      a mirror of `upstream-incoming` (lines 89–90).

### Code, separate commits (O18)

- [ ] `modules/slots/jj/pre-push.sh:65-67` — invert the gate, or correct
      `modules/slots/jj/default.nix:54`. Decide which behavior is intended first.
- [ ] `modules/slots/jj/pre-push.sh:10` — read `PRE_COMMIT_REMOTE_NAME`, not
      `${PRE_COMMIT_REMOTE_BRANCH%%/*}`.
- [ ] `modules/slots/jj/pre-push.sh:69` — use the `range` bounds, so the zero sha never
      reaches `git diff`.
- [ ] Add the structural lock gate (research § 8, assertion 7) to a `checks/` derivation
      or to the push path. A name-only or pattern-only check cannot catch a lock-node
      leak.
- [ ] Extend `kdn.jj.fork.deniedFilePatterns` with the spelling that appears in the
      fork-only lock node keys and their `url` fields. Confirm the fix with
      `jj fork-audit -q --color=never <the mixed commit>`; it must exit 1.
- [ ] `modules/slots/jj/fork/check-fork-contamination.sh` — the hook runs at `pre-commit`
      and reads the git index, so jj never triggers it. Decide whether to move the content
      check to the push path or to drop the hook.

## Exit criteria

- [ ] Every doc, rule and skill states the fetch step and the reconcile branch.
- [ ] Every doc, rule and skill states the start-state table, and which states need work
      first.
- [ ] The completion check exists as a runnable script, and it FAILs on the current
      incomplete state and PASSes on a finished update.
- [ ] The `devenv.lock` strip list holds no hardcoded prefix, and an empty list stops the
      run.
- [ ] Every relative link in the four doc and rule files, and in both skills, resolves.
- [ ] The public-chain leak gate is structural, and it does not depend on the pattern list.
- [ ] `jj fork-audit -q --color=never 'upstream-tip'` exits 0 on a finished update.

## Out of scope

- The current update in the working copy. Do not run it, and do not repair the graph as
  part of this task. This task changes documents and adds a check.
- Contribution access tiers. Another task owns
  `docs/tasks/fork-contribution-access-tiers*.md`.
- The `flake-lock-merge` tool itself. Its behavior is correct; only the docs around it
  need work.
- `docs/jujutsu-vcs.fork.md` and `checks/jj-experiments/`. Both are accurate and the
  corrected procedure reuses them.
