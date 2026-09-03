---
type: Reference
description: Golden paths to push a change to a branch or fork, proven by test_push.py; also the worked example of how to extend the harness.
timestamp: 2026-09-03T00:00:00+02:00
---

# Push a change to a branch or fork

Branch-agnostic day-to-day operation. The executable proof is `test_push.py`
(plain repos, no fork slot). This group is also the **reference example** for
adding a test group — read the last section to learn the harness by copying it.

## The golden path

```bash
jj git fetch --remote=<remote>            # 1. see the real remote state
jj rebase -b @ -d <branch>@<remote>       # 2. move your work onto the incoming tip (skip if ahead)
jj bookmark set <branch> -r <your-rev>    # 3. point the branch at your work
jj git push --remote=<remote> -b <branch> # 4. publish
```

The fork case is the same command with `--remote=<fork>`.

## Publish a new branch

- **Anonymous branch for a PR — the usual case.** `jj git push -c <rev>` creates
  an auto-named `push-<change-id-prefix>` bookmark and pushes it. No branch name
  needed. Proven by `test_publish_anonymous_pr_branch`.
- **Named branch.** `jj bookmark create <name> -r <rev>` then
  `jj git push --remote=<remote> -b <name>`. jj 0.44 has **no `--allow-new`
  flag**; the push creates the remote bookmark and starts tracking it, so a later
  push of the same branch just works. Proven by
  `test_publish_named_branch_tracks_no_allow_new`.

## Step 2 — reconcile with the incoming commits

After the fetch, your local work and the fetched `<branch>@<remote>` are two
heads. You put your work on top of the incoming tip.

- **Approach B — move your work onto the incoming (golden default).**
  - Whole stack: `jj rebase -b @ -d <branch>@<remote>`. It replays every mutable
    commit that leads to `@`, order kept, and does not rewrite the fetched
    commits. Proven by `test_behind_whole_stack_rebase_b`.
  - One change: `jj rebase -r <tip> -d <branch>@<remote>`. It moves only that
    commit; jj reparents its descendants onto its former parent, so a lower
    commit stays on the old base. Proven by `test_behind_tip_only_rebase_r`.
- **Approach A — land the incoming *under* your work — depends on the target.**
  `jj rebase -r <branch>@<remote> --insert-before @` is **refused when the target
  is immutable**: the trunk `main@<remote>` (always, even when tracked), or any
  **untracked** remote bookmark. Proven by
  `test_insert_incoming_refused_for_trunk_or_untracked`. It **succeeds** on a
  **tracked, non-trunk feature branch** — `jj bookmark track feat@origin` first,
  then insert, then `jj git push -b feat`; the local `feat` then diverges from
  `feat@origin`. Proven by `test_insert_incoming_succeeds_on_tracked_feature`.
  For the primary branch you cannot move the incoming — use Approach B.

## Push safety — a stale push is rejected; a post-fetch push can clobber

jj push uses force-with-lease. A push made **before** you fetch the moved remote
is **rejected** with "stale info" — that is the real guard. Only **after** you
fetch does a bare push of a non-descendant stop failing and instead move the
bookmark **sideways**, discarding the remote's commit. So fetch, then rebase onto
the incoming tip (Approach B), which makes the push a fast-forward. Check first
with `jj git push … --dry-run`: "move sideways" means it would clobber. There is
no fast-forward-only flag. To avoid touching the primary at all, push a
feature/PR branch. Proven by `test_behind_whole_stack_rebase_b`.

## Fetched bookmarks are untracked

After `jj git fetch`, a remote bookmark arrives **untracked**. A push from that
repo only moves the branch after `jj bookmark track <name>@<remote>` (the branch
you pushed yourself is already tracked). This is why the "remote moved ahead"
test tracks first — see `advance_remote` in `topologies.py`.

## Extend the harness — a worked example

`test_push.py` is the reference for adding a group. To add or verify a jj recipe,
copy its shape:

- **Build state inline first, then extract when it repeats.** Each test started
  self-contained — its own repos and bare remotes via `register_remote`,
  `commit`, `bookmark_set`, `push`, `fetch` — so the whole flow read in one
  function. Once that setup repeated across tests, the shared scaffolding
  (`build_push_base`, `advance_remote`, `push_feature`) moved into
  `topologies.py`; the golden-path steps stayed inline, because those steps are
  the lesson. See `conftest.py` for the full `Repo` API.
- **Simulate a remote that moved ahead** with the two-repos-share-one-bare trick:
  a second repo registers the **same bare** (`register_remote(name, bare)`),
  tracks the bookmark, commits, and pushes; the first repo fetches and is behind.
  `topologies.advance_remote` shows it.
- **Assert with revsets, not text.** `Repo.ids("<revset>")` returns change ids.
  Use `<rev>::` for "descendants of" — not `<rev>..`, which is a different range
  operator. Read `Repo.log_graph` output when a test surprises you.
- **Commit times are deterministic** through the `Repo` builders, so `latest()`
  and the `*-tip` aliases resolve the same way on every run.
- **Pair a `test_<group>.py` with a `test_<group>.md`.** The `.py` is the proof;
  the `.md` is the prose. Write both in Simple Technical English, with placeholder
  names only — never a real sensitive term.
- **Run it hermetically:** `nix run .#jj-experiments-run -- -k <name>` (or
  `pytest -k <name>` inside the devenv shell). See
  [README.md](README.md) for the run modes and the throwaway-vs-committed rule.
