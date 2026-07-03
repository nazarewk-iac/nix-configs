---
name: jj-workflows
description: jj version control patterns — working copy, split/squash, bookmarks, fork rebase. Use when working with jj commits, splits, rebases, or bookmark management in this repo.
---

Full reference: [docs/jj-workflows.md](../../docs/jj-workflows.md)

## Key rules for agents

- **Never `jj edit` to read a file** — use `jj file show --revision <id> <path>` instead
- **Never pre-create commits** — accumulate changes in `@`, then `jj split` or `jj squash --into`
- **`jj split` / `jj describe` / `jj squash` open an editor** — always pass `-m 'msg'` and `-- <files>` in non-interactive contexts
- **Bookmarks go on `@-`** (the just-named commit), not `@` (the new empty working copy)
- **Rebase is a last resort** — only when graph topology genuinely needs fixing

## Working copy state

```bash
jj st                                           # what's changed
jj log --limit 8                                # recent graph
jj file show --revision <id> path/to/file       # read file from any revision
jj op log                                       # operation history
jj undo                                         # undo last operation (safe escape hatch)
```

## Commit flow

```bash
# make changes in @, then:
jj describe -m 'feat(...): description'         # name @; creates new empty @
jj split -m 'fix(...): desc' -- path/to/file    # carve off into named commit
jj squash --from @ --into <id> -m 'msg'         # fold into existing commit
jj bookmark set upstream -r @-                  # point bookmark at named commit
```

## Fork topology (when fork remote is configured)

```
upstream  ──► ...kdn-chain... ──► upstream bookmark
         \                              \
          \──────────── main ◄── @       (empty)
         /
main@<fork-remote>
```

New commits belong above `upstream` (kdn chain), not above `main` (the fork-merge).

```bash
# keep @ current:
jj rebase -s @ -d main -d upstream

# new fork merge commit:
jj new <kdn-tip> <fork-tip> -m 'chore(<fork>): merge'

# after adding kdn-side commits — advance bookmarks and restore @:
jj bookmark set upstream -r 'latest(upstream-candidates)'
jj rebase --revision <main-merge-id> --destination upstream --destination main@<fork-remote>
jj bookmark set main -r <main-merge-id>
jj new -d main -d upstream

# check for stray orphaned commits before finishing:
jj log -r '::(@ | main | upstream)' --no-graph \
  -T 'change_id.short() ++ " " ++ bookmarks ++ " " ++ description.first_line() ++ "\n"'
```
