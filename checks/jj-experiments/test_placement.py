"""Placement golden paths — where a new change lands in the fork topology.

Each test builds the frozen base tree, runs a golden-path placement recipe, and
asserts the post-conditions:

- generic content lands on the upstream chain (becomes ``upstream-tip``),
- ``fork-leaked`` stays empty,
- the frozen merge is not rewritten (same commit id) and stays an ancestor of
  ``@`` (so ``jj sync-remotes`` fast-forwards),
- the merge on top is mutable (built forward, not a rewrite).

See ``test_placement.md`` for the prose and the frozen-vs-mutable reasoning.
"""

from __future__ import annotations

import pytest

import topologies


@pytest.fixture
def base(mkrepo, harness):
    slot = harness.slot_config()
    repo = mkrepo()
    labels = topologies.build_base_tree(repo, slot)
    return repo, labels


def _one(repo, revset):
    ids = repo.ids(revset)
    assert len(ids) == 1, f"{revset} -> {ids}"
    return next(iter(ids))


def test_upstream_change_on_frozen_tree_unified_recipe(base):
    """Frozen tree: the two-command unified recipe places a generic change.

    ``jj new --no-edit -B @ -m 'chore(upstream): merge'`` makes a mutable merge;
    ``jj split -A upstream-tip -B fork-tip`` grafts the generic commit onto the
    old upstream tip and into the new merge.
    """
    repo, L = base
    m_cid = repo.commit_id(L["M"])

    repo.write("modules/foo.nix", "# generic\n")
    repo.jj("new", "--no-edit", "-B", "@", "-m", "chore(upstream): merge")
    repo.jj(
        "split", "-A", "upstream-tip", "-B", "fork-tip",
        "-m", "feat: generic foo", "--", "modules/foo.nix",
    )

    s = _one(repo, 'description(substring:"generic foo")')
    assert repo.ids(f"parents({s})") == {L["U2"]}   # child of the old upstream tip
    assert repo.ids("upstream-tip") == {s}          # now the upstream tip
    assert repo.ids("fork-leaked") == set()         # no leak
    assert repo.commit_id(L["M"]) == m_cid          # frozen merge not rewritten
    assert repo.ids(f'{L["M"]} & ::@') == {L["M"]}  # still an ancestor of @
    assert repo.ids("merge-frozen") == set()        # the new merge is mutable
    # the new merge is merge(old frozen merge, generic commit), and it is tree-merge:
    assert repo.ids("parents(tree-merge)") == {L["M"], s}


def test_second_upstream_change_into_existing_mutable_merge(base):
    """Mutable merge already present: a single split places the next change.

    After the first change the fork tip is a mutable merge. A second generic
    change needs only ``jj split -A upstream-tip -B fork-tip`` — the mutable
    merge is reparented onto the new commit, no ``jj new`` and no rebase. This is
    the "merge in the middle" case (confirmed live 2026-09-02).
    """
    repo, L = base
    # first change via the unified recipe → a mutable merge is now fork-tip
    repo.write("modules/foo.nix", "# generic\n")
    repo.jj("new", "--no-edit", "-B", "@", "-m", "chore(upstream): merge")
    repo.jj(
        "split", "-A", "upstream-tip", "-B", "fork-tip",
        "-m", "feat: generic foo", "--", "modules/foo.nix",
    )
    s1 = _one(repo, 'description(substring:"generic foo")')
    m_cid = repo.commit_id(L["M"])

    # second change: one placed split into the existing mutable merge
    repo.write("modules/bar.nix", "# generic 2\n")
    repo.jj(
        "split", "-A", "upstream-tip", "-B", "fork-tip",
        "-m", "feat: generic bar", "--", "modules/bar.nix",
    )

    s2 = _one(repo, 'description(substring:"generic bar")')
    assert repo.ids(f"parents({s2})") == {s1}       # stacks on the previous upstream tip
    assert repo.ids("upstream-tip") == {s2}
    assert repo.ids("fork-leaked") == set()
    assert repo.commit_id(L["M"]) == m_cid          # frozen merge still not rewritten
    assert repo.ids("merge-frozen") == set()


def test_fork_leaf_change_stays_above_the_merge(base):
    """Leaf fork tweak: a plain split leaves it above the merge, fork-side.

    A leaf/host tweak is fork-only. A plain ``jj split -m … -- <files>`` puts it
    above the merge on the fork chain. It becomes the fork tip, so a later sync
    pushes it to ``main@fork``. It never reaches upstream. ``fork-leaked`` lists
    it — that is informational for a leaf, not a gate.
    """
    repo, L = base
    m_cid = repo.commit_id(L["M"])
    repo.write("hosts/PLACEHOLDER-SENSITIVE-tweak.nix", "# leaf\n")
    repo.jj("split", "-m", "feat(fork): host tweak", "--", "hosts/PLACEHOLDER-SENSITIVE-tweak.nix")

    leaf = _one(repo, 'description(substring:"host tweak")')
    assert leaf in repo.ids("fork-chain")       # on the fork chain
    assert repo.ids("fork-tip") == {leaf}        # fork tip advances to it
    assert leaf in repo.ids("fork-leaked")       # informational: fork content above the merge
    assert leaf not in repo.ids("upstream-safe")
    assert repo.ids("upstream-tip") == {L["U2"]}  # upstream is untouched
    assert repo.commit_id(L["M"]) == m_cid        # merge untouched


def test_fork_base_change_folds_into_a_new_merge(base):
    """Durable fork-base change: fold it into a new merge on the fork side.

    On a frozen tree you cannot rewrite the fork chain below the immutable merge,
    so build forward: carve the fork commit after ``fork-tip``, then make a new
    merge of ``upstream-tip`` and that fork commit. The fork content ends up below
    the new merge (on the fork side), so ``to-rebase`` and ``fork-leaked`` stay
    empty and ``upstream-tip`` is untouched.
    """
    repo, L = base
    m_cid = repo.commit_id(L["M"])

    repo.write("hosts/PLACEHOLDER-SENSITIVE-base.nix", "# fork base\n")
    repo.jj("split", "-A", "fork-tip", "-m", "feat(fork): base wiring",
            "--", "hosts/PLACEHOLDER-SENSITIVE-base.nix")
    sfork = _one(repo, 'description(substring:"base wiring")')
    repo.jj("new", "upstream-tip", "fork-tip", "-m", "chore(upstream): merge")
    new_merge = repo.change_id("@")
    repo.new(new_merge)  # leave an empty @ on top; jj sync-remotes moves the bookmarks

    assert repo.ids(f"parents({new_merge})") == {L["U2"], sfork}  # merge(upstream-tip, fork commit)
    assert sfork in repo.ids("fork-chain")       # fork content on the fork side
    assert repo.ids("to-rebase") == set()        # nothing left above the merge
    assert repo.ids("fork-leaked") == set()      # and so no leak
    assert repo.ids("upstream-tip") == {L["U2"]}  # upstream untouched
    assert repo.ids("merge-frozen") == set()      # new merge is mutable
    assert repo.commit_id(L["M"]) == m_cid        # old frozen merge not rewritten
    assert repo.ids(f'{L["M"]} & ::@') == {L["M"]}  # still an ancestor


def test_mixed_working_copy_split_by_content(base):
    """A mixed ``@`` (generic + fork-sensitive) routes each part by content.

    Generic content goes onto the upstream chain via the unified recipe; the
    remaining sensitive content becomes a fork leaf above the merge. So the
    generic part never leaks, and only the sensitive leaf shows in `fork-leaked`.
    """
    repo, L = base
    m_cid = repo.commit_id(L["M"])
    repo.write("modules/generic.nix", "# generic\n")
    repo.write("hosts/PLACEHOLDER-SENSITIVE-x.nix", "# sensitive\n")

    # route the generic part down onto the upstream chain (unified recipe):
    repo.jj("new", "--no-edit", "-B", "@", "-m", "chore(upstream): merge")
    repo.jj("split", "-A", "upstream-tip", "-B", "fork-tip",
            "-m", "feat: generic part", "--", "modules/generic.nix")
    # the sensitive remainder stays in @ → carve it as a fork leaf above the merge:
    repo.jj("split", "-m", "feat(fork): sensitive part", "--", "hosts/PLACEHOLDER-SENSITIVE-x.nix")

    gen = _one(repo, 'description(substring:"generic part")')
    sens = _one(repo, 'description(substring:"sensitive part")')
    assert repo.ids("upstream-tip") == {gen}        # generic on the upstream chain
    assert gen not in repo.ids("fork-leaked")        # generic never leaks
    assert sens in repo.ids("fork-chain")            # sensitive on the fork chain
    assert repo.ids("fork-leaked") == {sens}         # only the sensitive leaf (informational)
    assert repo.commit_id(L["M"]) == m_cid           # frozen merge untouched
