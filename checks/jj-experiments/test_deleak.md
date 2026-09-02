---
type: Reference
description: Golden paths for de-leaking fork-sensitive content and for making one change depend on another, proven by test_deleak.py.
timestamp: 2026-09-02T00:00:00+02:00
---

# De-leak and cross-dependency (X→Y)

These recipes rewrite local work above the merge. That work is mutable (the merge
below is frozen), so `describe`/`split`/`rebase` on it is allowed. The proof is
`test_deleak.py`; the base graph is `topologies.build_base_tree`.

## Golden path — de-leak by splitting content

A commit above the merge mixes generic and fork-sensitive content, so it is
`fork-leaked`. Split the sensitive file out:

```bash
jj split -m 'feat(fork): sensitive part' -- <sensitive files>
```

jj keeps the selected files in the parent commit and the remainder in `@`. So the
sensitive part becomes its own fork commit and the generic remainder stays in `@`
and is now `upstream-safe`. Verified by `test_deleak_by_splitting_content`:
after the split, `fork-leaked` holds only the sensitive commit, and the generic
remainder is in `upstream-safe`.

## Golden path — de-leak by rewording

A commit whose content is generic can still be `fork-leaked` because its
description matches a denied message pattern. Reword it:

```bash
jj describe -m 'feat: neutral message'
```

`fork-leaked` then empties. Verified by `test_deleak_by_rewording`.

## Golden path — make X an ancestor of Y (X→Y dependency)

A fork change `Y` depends on a generic change `X` (for example host wiring that
uses a slot), but `X` is not yet in `Y`'s ancestry. Add `X` as a second parent of
`Y` while keeping `Y`'s existing parent:

```bash
jj rebase -s Y -d X -d <Y-existing-parent>
```

`Y` becomes a merge of `X` and its old parent, so `X` is now an ancestor of `Y`.
Verified by `test_make_x_an_ancestor_of_y`: `parents(Y)` lists both `X` and the
old parent, and `X & ::Y` is non-empty.

All three require the target commits to be mutable (above the frozen merge). You
cannot de-leak or re-parent a published/immutable commit — build forward instead
(see `test_hazards.md`).
