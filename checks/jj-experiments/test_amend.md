---
type: Reference
description: Day-to-day golden paths for amending or rewording a commit, proven by test_amend.py.
timestamp: 2026-09-03T00:00:00+02:00
---

# Amend / rework a commit

Branch-agnostic everyday paths. No fork slot needed. The executable proof is
`test_amend.py` (a plain `c1 <- c2` history).

## Golden path — amend in place with `jj edit`

Work directly inside an existing mutable commit:

```bash
jj edit <id>        # @ becomes that commit
# ...edit files...
jj new <tip>        # return to the tip (a bare `jj new` would child the edited commit)
```

- `@` is the commit itself; edits amend it on the next snapshot.
- The change id is stable; only the content and the git commit id change.
- Descendants rebase automatically (same change ids).
- Proven by `test_amend_in_place_with_jj_edit`.

## Golden path — amend via `jj squash --into`

When you made the fixup on top instead of sitting inside the commit:

```bash
# ...fixup edits in @...
jj squash --into <id>     # fold @ into that earlier commit
```

- The target commit gains the content; `@` no longer carries it.
- Proven by `test_amend_by_squash_into`.

## Golden path — reword (message only)

```bash
jj describe -r <id> -m 'new message'
```

- Changes the description only; content is unchanged and `@` does not move.
- Proven by `test_reword_changes_message_only`.

## Which one

- `jj edit <id>` — you want to work inside a commit for a while.
- `jj squash --into <id>` — you accumulated fixup edits in `@` and want to fold
  them down. See also `jj absorb` in `test_squash_absorb.md`, which auto-routes
  each hunk to the ancestor that last touched it.
- `jj describe -r <id>` — message-only change.

All three rewrite the commit, so they work only on **mutable** commits. A pushed
or immutable commit cannot be amended — build forward instead (see
`test_hazards.md`).
