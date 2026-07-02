# jj Workflows

> **Agent summary:** [.agents/rules/jj-workflows.md](../.agents/rules/jj-workflows.md)

Practical patterns for this repo. See also
[version-control.md](../.agents/rules/version-control.md) for the basic command reference,
and [flake-update.md](flake-update.md) for the concrete update workflow that uses these
patterns.

---

## The working copy (@)

`@` is always an empty, description-less change — your scratch space. You accumulate edits
there, then name or carve them up when you're happy with the result. jj creates a fresh empty
`@` automatically whenever `@` gains a description.

```bash
# edit files, then name whatever landed in @:
jj describe -m 'feat(...): description'
# @ is now named; a new empty @ appears on top automatically
```

Checkpoint before risky work:

```bash
jj describe -m 'wip: checkpoint'
# work in new @...
jj abandon @    # rolls back to the checkpoint if things go wrong
```

### Preferred flow: split and squash, not rebase

**Never create a new commit before making the changes.** Let edits accumulate in `@`, then:

- Use `jj split` to carve `@` into multiple named commits.
- Use `jj squash --from @ --into <target>` to fold `@` into an existing unpushed commit.

**Rebase is a last resort** — it moves commits around and can scramble parent relationships,
especially in a fork workflow with multiple merge commits. Prefer:

```bash
# wrong: create commit, make changes, wrestle with rebases
jj new upstream -m 'feat: thing'
# ...make changes...
# now you need to rebase everything to fix the topology

# right: make changes in @, then split/squash into the right place
# ...make changes in @...
jj split -m 'feat: thing' -- path/to/file          # carve off into named commit
jj squash --from @ --into <change-id> -m 'msg'     # fold into existing commit
```

The only time to reach for `jj rebase` is when the graph topology genuinely needs changing
(e.g. after `jj sync-upstream` pulls in new kdn commits that the fork merge must absorb).

---

## Without a fork (upstream-only)

`upstream` bookmark tracks the public kdn tip. `@` sits directly on top of it:

```
main@kdn ──► ... ──► upstream ──► @
```

After fetching, keep `@` current:

```bash
jj git fetch --remote=kdn
jj rebase -s @ -d upstream    # or: -d main@kdn
```

---

## With a fork remote

When a private fork remote exists alongside kdn, `main` is a merge of both lines and `@` sits
on top of both `main` and `upstream`:

```
main@kdn ──► ...kdn-chain... ──► upstream
         \                              \
          \──────────────── main ──────► @
         /
main@<fork-remote> ──► ...fork-chain...
```

After fetching both remotes, keep `@` current:

```bash
jj git fetch --remote=kdn --remote=<fork-remote>
jj rebase -s @ -d main -d upstream
# equivalently:
jj rebase -s @ -d main -d main@kdn
```

---

## Splitting changes

`jj split` is the primary tool for carving accumulated work into separate commits. It opens an
editor interactively by default — great when working in a terminal. Pass `-m` and `--` to skip
the editor:

```bash
jj split                                        # interactive: pick hunks/files
jj split -m 'fix(...): desc' -- path/to/file    # non-interactive: by file
```

After splitting, the selected changes become `@-` (named) and a fresh empty `@` sits on top.

---

## Bookmark hygiene

`jj describe` names `@` and advances `@` forward — the named commit is now `@-`. Point
bookmarks at `@-`, not `@`:

```bash
jj describe -m 'chore(flake): update'
jj bookmark set upstream -r @-
# or by explicit change ID (unambiguous, good in scripts):
jj bookmark set upstream -r <change-id>
# or by revset when working in a fork context:
jj bookmark set upstream -r 'latest(upstream-candidates)'
```

---

## Rebasing the fork merge after new kdn commits

When new commits land on the kdn side (e.g. post-update fixes), rebase the fork merge commit
to include them, then restore `@` on top of both:

```bash
jj rebase --revision <merge-change-id> \
          --destination upstream \
          --destination main@<fork-remote>
jj bookmark set main -r <merge-change-id>
jj rebase -s @ -d main -d upstream
```

See [flake-update.fork.md](flake-update.fork.md) for the concrete workflow.
