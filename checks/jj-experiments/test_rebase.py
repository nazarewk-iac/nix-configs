"""Pull-upstream / rebase golden paths — integrate new upstream commits.

See ``test_rebase.md`` for the prose and the frozen-vs-mutable reasoning.
"""

from __future__ import annotations

import pytest

import topologies


@pytest.fixture
def incoming(mkrepo, harness):
    slot = harness.slot_config()
    repo = mkrepo()
    labels = topologies.build_incoming_tree(repo, slot)
    return repo, labels


def test_incoming_tree_has_unmerged_upstream(incoming):
    repo, L = incoming
    assert repo.ids("upstream-incoming") == {L["P1"], L["P2"]}
    assert repo.ids("upstream-incoming-tip") == {L["P2"]}
    assert repo.ids("upstream-tip") == {L["P2"]}
    assert repo.ids("fork-tip") == {L["M"]}
    assert repo.ids("merge-frozen") == {L["M"]}


def test_pull_upstream_frozen_builds_new_merge(incoming):
    """Frozen tree: integrate new upstream by building a new merge.

    The current merge is published (immutable), so you cannot rebase the chain
    below it. Build a new merge of ``fork-tip`` and the new upstream tip. The old
    frozen merge stays an ancestor; the new merge is mutable.
    """
    repo, L = incoming
    m_cid = repo.commit_id(L["M"])

    repo.jj("new", "fork-tip", "upstream-incoming-tip", "-m", "chore(upstream): merge")
    new_merge = repo.change_id("@")
    repo.new(new_merge)  # leave an empty @ on top; jj sync-remotes moves the bookmarks

    assert repo.ids(f"parents({new_merge})") == {L["M"], L["P2"]}  # merge(old merge, new upstream)
    assert repo.ids("upstream-incoming") == set()   # all upstream integrated
    assert repo.ids("fork-leaked") == set()          # no leak
    assert repo.ids("merge-frozen") == set()         # the new merge is mutable
    assert repo.commit_id(L["M"]) == m_cid           # old frozen merge not rewritten
    assert repo.ids(f'{L["M"]} & ::@') == {L["M"]}   # still an ancestor


def test_pull_upstream_mutable_rebases_the_chain(mkrepo, harness):
    """Mutable tree: rebase the local upstream chain onto the new upstream.

    The current merge is not published, so integrate by rebasing the local
    upstream chain (``roots(upstream-local)``) onto the new upstream tip. The
    same merge is reused (no second merge). The published base merge below stays
    immutable.
    """
    slot = harness.slot_config()
    repo = mkrepo()
    L = topologies.build_mutable_incoming_tree(repo, slot)

    assert repo.ids("upstream-local") == {L["UL1"]}
    assert repo.ids("merge-frozen") == set()          # M1 is mutable
    assert repo.ids("tree-merge") == {L["M1"]}
    m0_cid = repo.commit_id(L["M0"])

    repo.jj("rebase", "-s", "roots(upstream-local)", "-d", "upstream-incoming-tip")

    assert repo.ids("tree-merge") == {L["M1"]}          # same merge reused
    assert repo.ids(f'parents({L["UL1"]})') == {L["P2"]}  # local upstream now on the new tip
    assert repo.ids("upstream-incoming") == set()        # all upstream integrated
    assert repo.ids("fork-leaked") == set()
    assert repo.commit_id(L["M0"]) == m0_cid             # published base merge not rewritten


def test_conflict_on_integration_detect_and_resolve(mkrepo, harness):
    """A file changed by both local work and new upstream conflicts on merge.

    Detect the conflict with ``conflicts()``, resolve by writing the merged
    content and letting jj snapshot, then confirm the tree is clean.
    """
    slot = harness.slot_config()
    repo = mkrepo()
    topologies.build_conflict_tree(repo, slot)

    repo.jj("new", "fork-tip", "upstream-incoming-tip", "-m", "chore(upstream): merge")
    merge = repo.change_id("@")
    assert repo.ids("conflicts()") == {merge}   # the new merge is conflicted

    repo.write("conf.txt", "resolved\n")         # resolve the conflict
    repo.jj("status")                             # snapshot the resolution
    assert repo.ids("conflicts()") == set()       # clean tree
    assert repo.ids("fork-leaked") == set()
