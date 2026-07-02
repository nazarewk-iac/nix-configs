# jj Workflows

Full doc: [docs/jj-workflows.md](docs/jj-workflows.md)

> In non-interactive contexts (scripts, agents), always pass `-m 'message'` and `-- <files>`
> to `jj split`, `jj describe`, `jj squash` — they open an editor by default.

## The working copy (@)

`@` is always an empty scratch change. Accumulate edits, then name with `jj describe`.
jj auto-creates a new empty `@` whenever `@` gains a description.

**Preferred flow: split and squash — rebase is a last resort.**
Never pre-create a commit before making changes. Let edits land in `@`, then carve them up:
- `jj split -m 'msg' -- <files>` — extract into a named commit
- `jj squash --from @ --into <id> -m 'msg'` — fold into an existing unpushed commit
Only use `jj rebase` when graph topology genuinely needs fixing (e.g. after sync-upstream).

## Key patterns

```bash
# name current changes:
jj describe -m 'feat(...): description'

# split @ into two commits non-interactively:
jj split -m 'fix(...): desc' -- path/to/file

# point bookmark at the just-named commit (not the new empty @):
jj bookmark set upstream -r @-
# or by change ID / revset:
jj bookmark set upstream -r <change-id>
jj bookmark set upstream -r 'latest(upstream-candidates)'

# keep @ current after fetching (no fork):
jj git fetch --remote=kdn
jj rebase -s @ -d upstream

# keep @ current (with fork):
jj git fetch --remote=kdn --remote=<fork-remote>
jj rebase -s @ -d main -d upstream

# rebase fork merge after new kdn commits, then restore @:
jj rebase --revision <merge-change-id> --destination upstream --destination main@<fork-remote>
jj bookmark set main -r <merge-change-id>
jj rebase -s @ -d main -d upstream
```
