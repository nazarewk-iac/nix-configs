"""Hazards and forbidden operations in the fork topology.

Each test is a worked example of something you must NOT do (and what jj does when
you try), or a subtle trap. See ``test_hazards.md`` for the prose.
"""

from __future__ import annotations

import topologies


def _parents(repo, rev):
    return repo.ids(f"parents({rev})")


def test_cannot_rewrite_a_pushed_commit(mkrepo, harness):
    """A published commit (main@fork) is immutable — describe/amend fails."""
    slot = harness.slot_config()
    repo = mkrepo()
    labels = topologies.build_base_tree(repo, slot)
    for target in (labels["M"], labels["U2"]):
        r = repo.jj("describe", target, "-m", "rewritten", check=False)
        assert r.returncode != 0, f"describe of {target} should fail"
        assert "immutable" in r.stderr.lower()


def test_cannot_squash_into_an_immutable_commit(mkrepo, harness):
    """Squashing into a published commit fails — build forward instead."""
    slot = harness.slot_config()
    repo = mkrepo()
    labels = topologies.build_base_tree(repo, slot)
    repo.write("modules/extra.nix", "# extra\n")
    r = repo.jj("squash", "--into", labels["M"], check=False)
    assert r.returncode != 0
    assert "immutable" in r.stderr.lower()


def test_latest_tip_follows_commit_time_not_topology(mkrepo, harness):
    """``upstream-tip`` = ``latest(upstream-chain)`` picks by commit time.

    A commit that is the topological tip but has an older commit time does NOT
    win the tip. The fix is to control the commit time.
    """
    slot = harness.slot_config()
    repo = mkrepo()
    labels = topologies.build_base_tree(repo, slot)

    # X and Y are generic upstream-side commits; Y is the topological tip but
    # gets an OLDER commit time than X.
    repo.new(labels["U2"])
    repo.write("a.nix", "a\n")
    repo.describe("feat: X newer time", ts=2_000_000_000)
    x = repo.change_id("@")
    repo.new(x)
    repo.write("b.nix", "b\n")
    repo.describe("feat: Y older time", ts=1_900_000_000)
    y = repo.change_id("@")

    # hazard: the tip is X (newer time), not the topological tip Y:
    assert repo.ids("upstream-tip") == {x}
    # fix: give the intended tip a newer commit time:
    repo.describe("feat: Y fixed time", rev=y, ts=2_100_000_000)
    assert repo.ids("upstream-tip") == {y}


def test_describing_a_dual_parent_working_copy_keeps_both_parents(mkrepo, harness):
    """A dual-parent ``@`` describes into a two-parent merge, not a clean commit.

    After a publish you stack work on a dual-parent ``@``. If you ``describe`` it,
    it becomes a described merge that keeps BOTH parents (including the fork
    parent). Commit upstream-side work on a single-parent ``@`` instead.
    """
    slot = harness.slot_config()
    repo = mkrepo()
    labels = topologies.build_incoming_tree(repo, slot)

    # dual-parent @ = both tips as parents (fork tip + new upstream tip):
    repo.jj("new", "fork-tip", "upstream-incoming-tip")
    assert len(_parents(repo, "@")) == 2

    # pitfall: describing it keeps two parents (a merge, not a clean commit):
    repo.jj("describe", "-m", "feat: oops upstream work", "@")
    assert len(_parents(repo, "@")) == 2

    # safe alternative: a single-parent @ for upstream-side work:
    repo.jj("new", "upstream-incoming-tip")
    assert len(_parents(repo, "@")) == 1

    # describing the single-parent @ keeps one parent → a clean non-merge commit:
    repo.jj("describe", "-m", "feat: clean upstream work", "@")
    assert len(_parents(repo, "@")) == 1
    assert repo.ids("@ & merges()") == set()
