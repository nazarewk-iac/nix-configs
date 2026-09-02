---
type: Reference
description: Read-only jj golden paths — inspect files and the graph safely and non-interactively. Proven by test_inspect.py.
timestamp: 2026-09-03T00:00:00+02:00
---

# Inspect / read golden paths

How to read files and the graph without a checkout and without an editor or
pager. Branch-agnostic. Proof: `test_inspect.py`.

## Read a file at any revision

Never `jj edit` a commit just to read it. Show the file directly:

```bash
jj file show -r <rev> <path>
```

Proven by `test_file_show_reads_a_file_at_a_revision`. This is also a read-only
cross-revision diff engine when piped (for example
`diff <(jj file show -r A f) <(jj file show -r B f)`).

## Diff one commit, or between two revisions

```bash
jj diff -r <id>                 # the change one commit makes
jj diff -r <id> --name-only     # just the paths
jj diff -r <id> --stat          # per-file +/- summary
jj diff --from <X> --to <Y>     # the change from X to Y
```

Proven by `test_diff_of_a_commit_lists_changed_paths` and
`test_diff_between_two_revisions`.

## `jj status` shows only the working copy

`jj status` (aka `jj st`) reports the working copy. It takes **no** `-r` — `jj
st -r <rev>` errors in this jj version. To inspect another revision, use `jj
diff -r <rev>` or `jj show <rev>`.

```bash
jj show <rev>     # metadata + diff of one commit
```

Proven by `test_status_has_no_revision_flag_use_diff_instead` and
`test_show_displays_a_commit`.

## Read the graph with a template, non-interactively

```bash
jj log --no-pager -r '<revset>' -T '<template>'
```

Always pass `--no-pager` in a non-interactive shell so jj does not hang on a
pager. A template reads exactly the fields you ask for, for example
`change_id.shortest(8) ++ " " ++ description.first_line() ++ "\n"`. Proven by
`test_log_template_reads_the_graph_non_interactively`.
