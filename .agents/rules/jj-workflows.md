# jj Workflows

Full doc: [docs/jj-workflows.md](docs/jj-workflows.md) — for implementation details invoke the `jj-workflows` skill.

> **Non-interactive:** always pass `-m 'msg'` and `-- <files>` to `jj split`/`jj describe`/`jj squash` — they open an editor by default.
> **Always pass `-- <files>` to `jj squash --into`** — squashing without a file list silently folds everything in `@`, including unexpected diffs from prior rebases.
> **Never `jj edit` to read a file** — use `jj file show --revision <id> <path>`.

## Required finish state

After any work session, `@` must be empty with the correct parents:
- **Fork repo:** `@` has both `main` and `upstream` as parents
- **Plain repo:** `@` has one parent (the tip of main)

```bash
# fork repo finish:
jj bookmark set upstream -r 'latest(upstream-candidates)'
jj rebase --revision <main-merge-id> --destination upstream --destination main@<fork-remote>
jj bookmark set main -r <main-merge-id>
jj new -d main -d upstream
```

In repos without a fork: just leave an empty `@` on top of the main branch (`jj new` after the last named commit).

> **Warning:** `jj describe` on a multi-parent `@` (e.g. when `@` sits on top of `main` + `upstream`) creates a merge commit inheriting all parents — including fork ones. Always commit kdn work while `@` has a single kdn parent, then restore the multi-parent `@` with `jj new -d main -d upstream` afterwards.

**Before declaring done:**
```bash
# 1. check for stray commits (orphans from rebases):
jj log -r '::(@ | main | upstream)' --no-graph -T 'change_id.short() ++ " " ++ bookmarks ++ " " ++ description.first_line() ++ "\n"'

# 2. fork repos only — verify no fork commits leaked into the kdn chain
# (grep for fork-remote name; the only allowed match is main@kdn/upstream@<fork-remote> at the base):
jj log -r 'main@kdn..upstream' --no-graph -T 'change_id.short() ++ " parents=" ++ parents.map(|p| p.change_id().short() ++ "(" ++ p.bookmarks() ++ ")").join(",") ++ " " ++ description.first_line() ++ "\n"' | grep "<fork-remote>" | grep -v "main@kdn"
# and verify upstream has exactly one parent:
jj log -r 'parents(upstream)' --no-graph -T 'change_id.short() ++ " " ++ bookmarks ++ " " ++ description.first_line() ++ "\n"'

# 3. verify the build:
devenv build
```

If `upstream` has more than one parent, rebase it onto just the kdn chain tip:
```bash
jj rebase --revision upstream --destination <kdn-chain-tip-id>
jj bookmark set upstream -r upstream
```

Ask the user whether to squash, relocate, or abandon any strays found. Fix build errors before finishing.
