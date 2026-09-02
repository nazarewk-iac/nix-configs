"""Revset-alias tests over the reference fork topology.

This finishes the `jj-fork-revset-pytest-suite` task: it asserts every fork
revset alias resolves to the expected change set on a known graph, and it proves
the `~fork` vs `~fork-direct` subtlety. See `test_revsets.md` for the prose.

These tests need the rendered fork aliases (`JJ_FORK_CONFIG_TOML`). Without it,
`harness.slot_config()` skips them, so a bare `pytest` run stays green.
"""

from __future__ import annotations

import pytest

import topologies


def _labels(labels, *names):
    return {labels[name] for name in names}


@pytest.fixture
def reference(mkrepo, harness):
    """A frozen reference tree with the fork aliases installed."""
    slot_cfg = harness.slot_config()
    repo = mkrepo()
    labels = topologies.build_reference(repo, slot_cfg, push_main_fork=True)
    return repo, labels


def test_tree_merge_is_the_single_merge(reference):
    repo, labels = reference
    assert repo.ids("tree-merge") == _labels(labels, "M")


def test_upstream_incoming_is_fetched_but_unmerged(reference):
    repo, labels = reference
    assert repo.ids("upstream-incoming") == _labels(labels, "P1", "P2")
    assert repo.ids("upstream-incoming-tip") == _labels(labels, "P2")


def test_to_rebase_is_local_described_work_above_the_merge(reference):
    repo, labels = reference
    assert repo.ids("to-rebase") == _labels(labels, "L1", "L2", "L3")


def test_fork_direct_matches_content_only(reference):
    repo, labels = reference
    assert repo.ids("fork-direct") == _labels(labels, "F1", "L2")


def test_upstream_safe_is_the_clean_subset(reference):
    repo, labels = reference
    assert repo.ids("upstream-safe") == _labels(labels, "L1", "L3")


def test_fork_leaked_is_sensitive_work_above_the_merge(reference):
    repo, labels = reference
    assert repo.ids("fork-leaked") == _labels(labels, "L2")


def test_fork_trap_drops_safe_local_changes(reference):
    # `~fork` tags every descendant of main@fork, so it drops even the clean
    # local changes; `upstream-safe` must use `~fork-direct` instead.
    repo, labels = reference
    assert repo.ids("to-rebase & ~fork") == set()
    assert repo.ids("to-rebase & ~fork-direct") == _labels(labels, "L1", "L3")


def test_upstream_local_is_the_pre_merge_upstream_chain(reference):
    repo, labels = reference
    assert repo.ids("upstream-local") == _labels(labels, "U1", "U2")


def test_pushed_reachability(reference):
    # `::remote_bookmarks()` also reaches jj's virtual root commit; exclude it
    # with `~root()` so the assertion covers the meaningful set.
    repo, labels = reference
    assert repo.ids("pushed & ~root()") == _labels(labels, "A", "P1", "P2", "U1", "U2", "F1", "M")
    assert repo.ids("pushed-fork & ~root()") == _labels(labels, "A", "U1", "U2", "F1", "M")
    assert repo.ids("pushed-upstream & ~root()") == _labels(labels, "A", "P1", "P2")


def test_tips_resolve_by_time(reference):
    repo, labels = reference
    assert repo.ids("upstream-tip") == _labels(labels, "U2")
    assert repo.ids("fork-tip") == _labels(labels, "L3")


def test_chains(reference):
    repo, labels = reference
    assert repo.ids("fork-chain") == _labels(labels, "F1", "M", "L1", "L2", "L3")
    assert repo.ids("upstream-chain") == _labels(labels, "A", "P1", "P2", "U1", "U2")


def test_merge_frozen_when_pushed(reference):
    repo, labels = reference
    assert repo.ids("merge-frozen") == _labels(labels, "M")


def test_merge_mutable_when_unpushed(mkrepo, harness):
    slot_cfg = harness.slot_config()
    repo = mkrepo()
    topologies.build_reference(repo, slot_cfg, push_main_fork=False)
    assert repo.ids("merge-frozen") == set()
