---
type: Reference
description: Golden paths for pulling new upstream into the fork topology, proven by test_rebase.py.
timestamp: 2026-09-02T00:00:00+02:00
---

# Pull-upstream / rebase golden paths

How to integrate new upstream commits into the fork. The executable proof is
`test_rebase.py`; the fixture is `topologies.build_incoming_tree`.

## Incoming state

`build_incoming_tree` publishes the base (`main@fork` = merge `M`), then the
public remote advances: `P1`, `P2` are children of `U2`, and `main@upstream` =
`P2`. They are fetched but not merged, so:

```
A ── U1 ── U2 ── P1 ── P2       upstream-tip = P2 (= upstream-incoming-tip); main@upstream = P2
│           \
│            M ── @             M = merge; main, main@fork = M (frozen); fork-tip = M
│           /
└── F1
```

`upstream-incoming` = `{P1, P2}`, `merge-frozen` = `{M}`.

## Golden path — frozen tree: build a new merge

The current merge is published, so you cannot rebase the chain below it. Build a
new merge of the fork tip and the new upstream tip:

```bash
jj git fetch --all-remotes            # bring the new upstream in
jj new fork-tip upstream-incoming-tip -m 'chore(upstream): merge'
jj new                                 # leave an empty @ on top; jj sync-remotes moves the bookmarks
```

Verified post-conditions (`test_pull_upstream_frozen_builds_new_merge`):

- the new merge is `merge(old merge, new upstream tip)`;
- `upstream-incoming` is empty — all upstream is integrated;
- `fork-leaked` is empty;
- the new merge is mutable (`merge-frozen` empty);
- the old frozen merge keeps its commit id (not rewritten) and stays an ancestor
  of `@` — the precondition a later `jj sync-remotes` fast-forwards on.

`jj sync-remotes` then advances the `upstream` bookmark to the new tip and pushes.

## Golden path — mutable tree: rebase the local upstream chain

When the current merge is not yet published, do not build a second merge. Rebase
the local upstream chain onto the new upstream and reuse the merge. The fixture
`topologies.build_mutable_incoming_tree` models this: `main@fork` is a prior
published merge `M0`, the current merge `M1` above it is mutable, `UL1` is a
local upstream commit not on the public remote (`upstream-local` = `{UL1}`).

```bash
jj git fetch --all-remotes
jj rebase -s 'roots(upstream-local)' -d 'upstream-incoming-tip'
jj new                                 # leave an empty @ on top; jj sync-remotes moves the bookmarks
```

Verified post-conditions (`test_pull_upstream_mutable_rebases_the_chain`):

- the same merge is reused (`tree-merge` keeps its change id — no second merge);
- the local upstream chain is rebased onto the new upstream tip
  (`parents(UL1)` becomes the new tip);
- `upstream-incoming` empties; `fork-leaked` stays empty;
- the published base merge below keeps its commit id (not rewritten).

This works only because the current merge is mutable. On a fully frozen tree the
merge and the chain below it are immutable, so use the new-merge path above.

## Golden path — conflict on integration

When new upstream and local work change the same file, integrating them
conflicts. jj records the conflict in the merge commit rather than stopping.

```bash
jj new fork-tip upstream-incoming-tip -m 'chore(upstream): merge'
jj log -r 'conflicts()'                # the new merge is listed
# edit each conflicted file to the merged content, then let jj snapshot:
jj status                              # (any jj command snapshots the resolution)
jj log -r 'conflicts()'                # now empty
```

Verified post-conditions (`test_conflict_on_integration_detect_and_resolve`):
`conflicts()` lists the new merge, then is empty after writing the resolved file
and snapshotting; `fork-leaked` stays empty.

## Inspect what you fetched

Before you integrate, read the topology of what a fetch brought in. Proven by
`test_inspect_incoming_after_fetch` (branch-agnostic; needs no fork slot).

```bash
jj git fetch --all-remotes
jj op show @                              # what THIS fetch changed: arrived commits + moved bookmarks
jj op diff --from @- --to @               # the same, as a diff between two operations
jj log -r '@..main@<remote>'              # ALL incoming commits (the full new range)
jj log -r 'main@<remote>..@ & ~empty()'   # your divergence; empty ⇒ strictly behind (fast-forward)
jj log -r 'heads(::@ & ::main@<remote>)'  # the merge base (last shared commit)
```

Verified caveats:

- Use `@..<incoming>` for the **whole** incoming range. `<incoming> ~ ::@` reports
  only the **tip** — a bookmark resolves to one commit, so it hides the rest.
- `<incoming>..@` lists commits you have that the incoming lacks; add `& ~empty()`
  to drop the empty working copy. Empty result ⇒ no divergence, so a plain
  fast-forward; non-empty ⇒ you diverged and must rebase or merge to integrate.
- `jj op show @` right after a fetch is the clearest "what did I just pull in":
  it lists each arrived commit and every local/remote bookmark that moved.
