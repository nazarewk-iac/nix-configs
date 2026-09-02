---
type: Reference
description: Golden path for detecting and resolving jj conflicts the agent-safe way, proven by test_conflicts.py.
timestamp: 2026-09-03T00:00:00+02:00
---

# Conflict golden paths

Branch-agnostic conflict handling. The executable proof is `test_conflicts.py`.
A fork-specific conflict-on-integration case is in `test_rebase.py`.

## How jj handles a conflict

jj does not stop a command on a conflict. It records the conflict **inside the
commit** and moves on, so `@` (or the rebased commit) simply becomes conflicted.
You resolve it afterward at your own pace.

## Golden path — detect, inspect, resolve

```bash
# after a merge or rebase that conflicts:
jj log -r 'conflicts()'          # which commits are conflicted
jj resolve --list -r <rev>       # which files (run at the conflicted rev)
jj file show -r <rev> <path>     # inspect jj's conflict markers

# resolve the agent-safe way — edit the file to the merged content, then let
# any jj command snapshot it (never the interactive `jj resolve` picker: it
# opens a merge tool and hangs in an agent):
#   1. write the resolved content to each conflicted file
#   2. run any jj command (e.g. `jj status`) to snapshot
jj log -r 'conflicts()'          # now empty
```

If the conflict is in a commit other than `@`, `jj edit <rev>` first so the
markers materialize in the working copy, then write the resolution and snapshot.

## jj conflict markers

jj uses its own markers, not classic git ones. `jj file show` of a conflicted
file shows a block delimited by `<<<<<<<` … `>>>>>>>`, with a `%%%%%%%` diff
section (changes from the base to one side) and a `+++++++` section (the full
contents of the other side). `test_merge_conflict_detect_inspect_and_resolve`
asserts the `<<<<<<<`, `%%%%%%%`, and `>>>>>>>` markers are present.

## Verified cases

- `test_merge_conflict_detect_inspect_and_resolve` — a merge of two sides that
  edit the same line conflicts; `conflicts()` lists the merge, `jj resolve
  --list` names the file, the markers are jj's, and writing the merged content
  plus a snapshot clears it.
- `test_rebase_into_conflict_and_resolve` — a rebase that replays one edit over
  a conflicting edit makes the rebased commit conflicted; `jj edit` it, write the
  resolution, snapshot, clean.
- `test_resolve_list_reports_no_conflicts_when_clean` — on a clean tree
  `conflicts()` is empty and `jj resolve --list` exits non-zero with a
  "No conflicts" message.

## Caution

Never run interactive `jj resolve` (no `--list`) in an agent — it launches a
merge tool and hangs. Always resolve by writing files and snapshotting.
