---
type: Task
status: done
authored_by: agent
description: Add a golden path for pushing a local change to a specific branch or fork target, and ship it as the canonical worked example of how to use and extend the jj-experiments harness.
timestamp: 2026-09-03T00:00:00+02:00
---

# Push a change to a branch or fork

## Gap

The docs, the skill, and the harness cover how to *place* content in the fork
topology. They do not cover the plain workflow: you have a local change and you
want to **push it to a specific target** — the shared `main`/`master`, a feature
branch, or a second fork remote — after a fresh fetch, remediating the status.

## Second goal — a discoverable, "shining example" harness exercise

This use-case is small and self-contained, so it also becomes the **reference
exercise** for the harness: a reader opens `test_push.py` + `test_push.md` to
learn both the golden path AND how to add a new test group. The final commit
links it as the canonical harness-extension example (see Plan, phase 4).

## Golden path (verified in the harness)

Four plain steps. A reader holds them in the head:

```sh
jj git fetch --remote=<remote>            # 1. see the real remote state
jj rebase -b @ -d <branch>@<remote>       # 2. move your work onto the incoming tip (skip if ahead) — see "Step 2: two approaches"
jj bookmark set <branch> -r <your-rev>    # 3. point the branch at your work
jj git push --remote=<remote> -b <branch> # 4. publish
```

Status-remediation decision rule (step 2 is the only conditional one):

- `<branch>@<remote>..<your-rev>` is **non-empty** and `<your-rev>..<branch>@<remote>`
  is empty → you are **ahead** → skip step 2 (fast-forward).
- `<branch>@<remote>..<your-rev>` is empty or both ranges are non-empty → you are
  **behind or divergent** → run step 2 (reconcile with incoming), then push.
- **Publishing a new branch — two kinds:**
  - **Anonymous branch for a PR (usual case):** `jj git push -c <rev>`
    (`--change`) creates an auto-named `push-<changeid>` bookmark and pushes it.
    No branch name needed. Lead the doc with this.
  - **Named branch (native tracking):** `jj bookmark create <name> -r <rev>`,
    then `jj git push --remote=<r> -b <name>`. jj 0.44 has **no** `--allow-new`
    flag; the new bookmark pushes directly and starts tracking, so later pushes
    just work.

## Step 2 — reconcile with the incoming commits: two approaches

After the fetch, your local mutable work and the fetched `<branch>@<remote>` are
two heads. You put your work on top of the incoming tip in one of two ways. The
choice is a real decision; the harness confirms the exact jj-0.44 flag behavior.

- **Approach B — move your work onto the incoming (golden default).**
  `jj rebase -s 'roots(<your mutable set>)' -d <branch>@<remote>` (human form:
  `jj rebase -b @ -d <branch>@<remote>`). Your commits replay on top of the
  incoming tip; the fetched commits are **not** rewritten, so the result is safe
  to push. It is the same shape the fork "pull upstream" path uses with
  `roots(upstream-local)`. Sub-axis — how much of your stack moves:
  - whole stack (`-b @` / `-s 'roots(...)'`) — default; never leaves work behind.
  - one change (`-r <tip>`) — moves only the tip; jj reparents its descendants
    onto its former parent, so the rest of your local work stays put.
- **Approach A — land the incoming under your work (insert).** Insert the fetched
  commit into your local chain: `jj rebase -r <incoming> --insert-before <@ or
  @->`. jj 0.44 **refuses it when the target is immutable** — the trunk
  `main@<remote>` (always, even when tracked) or an **untracked** remote bookmark
  ("would rewrite N immutable commits"). It **succeeds on a tracked, non-trunk
  feature branch**: `jj bookmark track feat@<remote>` first, then insert, then
  `jj git push -b feat` (the local `feat` then diverges from `feat@<remote>`). So
  for the primary/shared branch you cannot move the incoming — use Approach B; for
  a feature branch, Approach A (track → insert → push) is available. (The fork
  "pull upstream" weave adds the incoming through a new merge, not by rewriting the
  remote commit; see `docs/jujutsu-vcs.fork.md`.)

Default for the shared/primary branch: **Approach B, whole stack** — the only
option there, since the incoming trunk is immutable. Approach A is available on a
tracked feature branch.

## Push safety — a stale push is rejected; a post-fetch push can clobber

`jj git push` is force-with-lease. A push made **before** you fetch the moved
remote is **rejected** with "stale info" ("references unexpectedly moved on the
remote") — that is the real guard. Only **after** you fetch does a bare push of a
non-descendant stop failing and instead **move the remote bookmark sideways and
discard the remote's commit** (returns 0). So the discipline is: fetch, then
rebase onto the incoming tip (step 2), so the push fast-forwards. `jj git push
--dry-run` prints "move sideways" when it would clobber; a clean run prints a
fast-forward. There is no fast-forward-only flag. Also: a freshly fetched bookmark
arrives **untracked** — run `jj bookmark track <name>@<remote>` before a push will
move it. To avoid touching the primary at all, push a feature/PR branch.

## Sub-cases the harness proves

| Case | Setup | Expected |
|---|---|---|
| Anonymous PR branch | remote has no such branch; publish one change | `jj git push -c <rev>` creates `push-<id>@<remote>` at the rev |
| Named tracked branch | remote has no such bookmark | `bookmark create` + push (no `--allow-new` in jj 0.44) publishes `<name>@<remote>`; it starts tracking |
| Fast-forward update | local work descends from `<branch>@<remote>` | set + push; remote bookmark advances; no rebase |
| Behind — B, whole stack | a second repo advanced `<branch>@<remote>`; local 2-commit stack | a pre-fetch push is rejected ("stale info"); after fetch, `-b @` replays both commits on the incoming tip, order kept, push fast-forwards; a bare post-fetch push would clobber sideways (`--dry-run` shows it) |
| Behind — B, tip only | same 2-commit stack | `-r <tip>` moves only the tip; the lower commit stays on the old base |
| Insert incoming — refused | target is the trunk `main@<remote>` or an untracked bookmark | `jj rebase -r … --insert-before @` errors "would rewrite immutable commits" |
| Insert incoming — tracked feature | track a non-trunk `feat@<remote>` | the insert succeeds; local `feat` diverges from `feat@<remote>`; `jj git push -b feat` publishes |
| Divergent | both local and remote advanced | the Approach B remediation resolves it |
| Second remote (fork) | two bare remotes registered | `--remote=<fork>` lands the branch on the fork bare, not on origin |

## Harness extension shape

- New files: `checks/jj-experiments/test_push.py` and a paired `test_push.md`.
- **Inline first, then extract.** Phase 2 writes each test self-contained, with
  its own state from `mkrepo`, `register_remote`, `bookmark_set`, `push`, `fetch`
  — a reader sees the whole flow in one function. A separate follow-up commit
  (phase 2b) refactors the shared setup into a reusable `topologies.py` builder,
  so the history itself shows the "start inline, extract when it repeats" method.
- **Simulate a remote that moved ahead** by composing existing helpers, exactly
  like `test_bookmarks.py::test_push_then_fetch_between_two_repos`: repo A pushes
  the branch, repo B registers the **same bare** (`register_remote(name, bare)`),
  commits, and pushes; repo A fetches and is now behind.
- **Deterministic commit times** through the `Repo` builders' auto-incrementing
  counter, like every group.
- No slot config needed — these tests are branch-agnostic and need no fork
  aliases, so they run under a bare `pytest` too.

## Discoverable exercise (the teaching layer)

- `test_push.md` reads as a worked walkthrough. It explains each fixture and
  helper it uses, the "two repos, one bare" divergence trick, the deterministic
  timestamps, and the paired-`.md` convention — so a reader learns to extend the
  harness by copying this group.
- `README.md` gets an "Extend the harness — worked example" pointer to
  `test_push`, next to the existing on-demand-runner section.
- The skill and the `jj-expert` agent gain a one-line pointer: "to add or verify
  a jj recipe, copy `test_push` as the template".

## Doc home

The golden path is branch-agnostic, so it lands in
`docs/jujutsu-vcs.md` (branch workflows / day-to-day) and is referenced from the
skill and from `docs/jujutsu-vcs.fork.md` (the fork case is `--remote=<fork>`).

## Plan and checkpoints

1. **Design** — this file. → checkpoint (await review).
2. **Implement (inline)** — `test_push.py` (self-contained functions) +
   `test_push.md` + the golden path in `docs/jujutsu-vcs.md`; verify the whole
   suite stays green. → checkpoint.
2b. **Extract** — a follow-up commit refactors the shared setup into a reusable
   `topologies.py` builder (the inline-first decision).
3. **Review + fix** — independent review of the new group, then a fix loop.
   → checkpoint.
4. **Link it** — a commit on top that markets `test_push` as the "shining
   example" of harness extension (README, skill, agent pointers).
