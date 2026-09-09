---
type: Task
description: Define one contribution procedure per access tier, so a fork collaborator or an outside contributor sends a change with no loss and no leak.
status: open
authored_by: agent
timestamp: 2026-09-09T00:00:00+02:00
---

# Contribution procedures by access tier

Research and evidence: [fork-contribution-access-tiers.research.md](research.md).
Read that file first. It tags every claim **verified** or **unverified**.

## Goal

Every fork procedure in this repo assumes one person who holds push access to both remotes. No
document states that assumption. Give each access tier its own procedure, and make the assumption
explicit in the docs that hold it today.

The load-bearing case: the maintainer is away for months. A person who can push only to the
private fork must submit an upstream-safe change. The change must survive, must leak no private
content, and must need no rework when the maintainer returns.

## Role vocabulary

| Role | Push access | Sends changes through |
|---|---|---|
| **maintainer** | the public remote **and** the private fork | direct push, `jj sync-remotes` |
| **fork collaborator** | the private fork only | a queue bookmark on the private fork |
| **outside contributor** | neither | a pull request against the public repo |

An **external adopter** ([../generalization-plan.md](../generalization/definition.md)) is a fourth,
separate role: an adopter *consumes* the modules in their own repo, while a contributor *sends
changes back* to this one.

## Work items

- [ ] Write `docs/contributing.md` (`type: How-To`). One section per role. Each section covers
      four change types: an upstream-safe change, a fork-only change, a flake update, and an
      upstream-safe change that sits on top of fork work.
- [ ] Add a "Roles and access tiers" section to `docs/jujutsu-vcs.fork.md`, after the TL;DR.
- [ ] Add an access-tier note to `docs/flake-update.fork.md`, above "Two rules that override
      everything".
- [ ] Record the measured `upstream-tip` / `fork-tip` hazard in `docs/jujutsu-vcs.fork.md`
      (research § A4). The `-A upstream-tip -B fork-tip` placement recipe means something else
      when local work sits above the merge.
- [ ] Make `jj sync-remotes` and `jj sync-upstream` unreachable for a non-maintainer. Add a
      `kdn.jj.fork.role` option to `modules/slots/jj/fork/default.nix`, with the values
      `maintainer` and `collaborator`. Emit the two sync aliases only for `maintainer`.
- [ ] Add a `jj queue` alias to the same slot. It runs the collaborator queue steps from the
      research file § C2 and refuses when the safety checks fail.
- [ ] Add a content-level safety check as one runnable command (research § E). `jj fork-audit`
      alone is not enough.
- [ ] **Move the push guard out of `.git/hooks/`.** Measured: `jj git push` fires no
      `.git/hooks/pre-push`, and `jj commit` fires no `.git/hooks/pre-commit` (research § A5,
      defect 3). So every fork push runs unchecked today, and `check-fork-contamination.sh` is
      dead code. The guard needs a wrapper command — a jj alias that runs the check, then pushes.
      Do this together with the defect-1 fix in
      [generalization-001-slots-sharing-readiness.md](../generalization/001-slots-sharing-readiness/definition.md);
      the defect-1 one-liner alone leaves every `jj git push` unprotected.
- [ ] Add `checks/jj-experiments` cases for the queue procedure and for the rebase-before-queue
      case.
- [ ] Separate "external adopter" from "outside contributor" in one sentence in
      `docs/generalization-plan.md`.

## Proposed edits to the current procedure docs

Described here, not applied. This pass changes no procedure file.

1. **`docs/jujutsu-vcs.fork.md`** — new section "Roles and access tiers" after the TL;DR, with the
   role table above. Add one clause to line 172 ("Bookmarks are moved by `jj sync-remotes`, not by
   hand"): only the maintainer runs `jj sync-remotes`.
2. **`docs/jujutsu-vcs.fork.md`** — extend the "Hazards" section with the measured tip hazard from
   research § A4, and add the current-tree evidence as the worked example.
3. **`docs/flake-update.fork.md`** — new note above line 23: the whole file assumes push access to
   both remotes. Point a reader without public access at `docs/contributing.md`.
4. **`docs/flake-update.fork.md`** — line 32 says "The user runs `jj sync-remotes` manually".
   Replace "The user" with "The maintainer".
5. **`docs/flake-update.md`** line 114 — the fork-free base doc reads `upstream@<fork-remote>`.
   Replace it with `main@<upstream-remote>`, so a reader with no fork can run the step.
6. **`docs/jujutsu-vcs.md`** lines 102-103 — the only place that names a role today. Point it at
   the role table instead of a bare "the maintainer".
7. **`.agents/rules/jujutsu-vcs.md`** and **`.agents/rules/flake-update.fork.md`** — replace "the
   user" with the role name, so an agent knows which tier it serves.
8. **New `docs/contributing.md`** — the three-tier procedure, and the public entry point for a
   collaborator and for an outside contributor.
9. **`modules/slots/jj/fork/default.nix`** — the `kdn.jj.fork.role` option and the `jj queue`
   alias from the work items.
10. **`modules/slots/jj/pre-push.sh`** — no edit here. The two measured defects belong to
    [generalization-001-slots-sharing-readiness.md](../generalization/001-slots-sharing-readiness/definition.md).
    Add a cross-reference from `docs/contributing.md` instead, so a collaborator knows that a
    public push has no content guard until checkpoint 001 lands.

## Exit criteria

- `docs/contributing.md` covers three roles and four change types, with no gap.
- A person who holds fork push access only queues an upstream-safe change with commands copied
  from the doc, with no edit.
- `jj sync-remotes` and `jj sync-upstream` do not exist for a `collaborator` role.
- The content-level safety check runs as one command and rejects a lock file.
- The queue procedure has a `checks/jj-experiments` case.
- Each fork doc names its access tier on the first screen.

## Out of scope

- The `pre-push.sh` fix. That is checkpoint 001.
- Any push. The maintainer reviews and pushes.
- Any change to `flake.lock`, `devenv.lock`, or `.flake.patches/`. The repo is mid-flake-update.
- A rename of the `kdn.*` namespace.
- CI on the public repo.
- The adopter path. That is [../generalization-plan.md](../generalization/definition.md).
