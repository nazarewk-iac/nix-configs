---
type: Reference
description: Day-to-day bookmark, sync, and untrack golden paths, proven by test_bookmarks.py.
timestamp: 2026-09-03T00:00:00+02:00
---

# Bookmarks, sync, and untrack

Branch-agnostic day-to-day operations. The executable proof is
`test_bookmarks.py` (plain repos, no fork slot).

## Bookmark CRUD

```bash
jj bookmark create <name> -r <rev>          # create
jj bookmark set    <name> -r <rev>          # move forward
jj bookmark set    <name> -r <rev> --allow-backwards   # move back/sideways
jj bookmark delete <name>                    # delete
jj bookmark list [--all-remotes]             # inspect
```

A forward move is allowed. A backward or sideways move is refused
("Refusing to move bookmark backwards or sideways") unless you pass
`--allow-backwards`. Proven by `test_bookmark_create_set_delete`.

## Sync — push then fetch (bare remote, headless)

```bash
# repo A:
jj bookmark set main -r <rev>
jj git push --remote origin --bookmark main   # auto-tracks a new bookmark

# repo B (same remote):
jj git fetch --remote origin
jj new main@origin                            # build on the fetched tip
```

`remote_bookmarks(remote="origin")` shows the pushed tip after the fetch. No
auth is needed against a local bare remote. Proven by
`test_push_then_fetch_between_two_repos`.

## Untrack — needs `.gitignore` first

```bash
jj file untrack <path>     # NOT `jj untrack`; the subcommand is `jj file untrack`
```

jj refuses to untrack a path that is not ignored ("Error: '<path>' is not
ignored. … Files that are not ignored will be added back by the next command").
So add the path to `.gitignore` first, then untrack. Proven by
`test_untrack_needs_gitignore_first`.
