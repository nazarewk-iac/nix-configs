# Version Control

This repo uses **Jujutsu (`jj`)** instead of raw git.

## Key commands

| Command | Purpose |
|---|---|
| `jj new -m "description"` | Create a new change (checkpoint) |
| `jj describe -m "..."` | Update current change description |
| `jj abandon @` | Discard current change, revert to parent |
| `jj squash` | Fold current change into its parent |
| `jj diff --from REV` | Compare against a previous state |

## Workflow

Create frequent small changes with `jj new` as checkpoints. This makes it easy to `jj abandon` if something breaks. Once a logical unit of work is done, squash related changes with `jj squash` so history stays clean.

- **Always leave an empty `jj` change on top** when finishing work — gives the user a clean working copy to review from
- **NEVER push changes** (user will review and push)
- Use conventional commit format (`feat:`, `docs:`, `chore:`, `fix:`)
