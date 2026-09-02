"""Move / restructure golden paths (branch-agnostic, no fork slot).

Reorder, split a committed commit, abandon, revert-forward, duplicate, and
simplify redundant merge parents. See ``test_restructure.md`` for the prose.
These use a plain repo (``JJConfig.without_slot()``) and need no fork config.
"""

from __future__ import annotations

import pytest


@pytest.fixture
def repo(mkrepo):
    return mkrepo()


def _one(repo, revset):
    ids = repo.ids(revset)
    assert len(ids) == 1, f"{revset} -> {ids}"
    return next(iter(ids))


def _commit_on(repo, parent, message, files):
    """Create a described commit on ``parent`` and return its change id."""
    repo.new(parent)
    for path, content in files.items():
        repo.write(path, content)
    repo.describe(message)
    return repo.change_id("@")


def test_reorder_two_changes(repo):
    """Move A to after B, so the order flips from A→B to B→A."""
    a = repo.commit("feat: a", {"a.txt": "a\n"})
    b = repo.commit("feat: b", {"b.txt": "b\n"})  # chain: root -> a -> b
    repo.jj("rebase", "-r", a, "--insert-after", b)
    assert repo.ids(f"parents({a})") == {b}           # a now follows b
    assert repo.ids(f"parents({b})") == repo.ids("root()")  # b now first


def test_split_committed_commit(repo):
    """``jj split -r`` carves a committed commit into two by content.

    The selected files go to the first (parent) commit with the ``-m`` message;
    the remainder stays in a child keeping the original message.
    """
    x = repo.commit("feat: x", {"x1.txt": "1\n", "x2.txt": "2\n"})
    repo.jj("split", "-r", x, "-m", "feat: x part1", "--", "x1.txt")

    selected = _one(repo, 'description(substring:"x part1")')
    remainder = _one(repo, 'description(substring:"feat: x") & ~description(substring:"part1")')
    assert repo.ids(f'{selected} & files("x1.txt")') == {selected}   # selected has x1
    assert repo.ids(f'{selected} & files("x2.txt")') == set()        # not x2
    assert repo.ids(f'{remainder} & files("x2.txt")') == {remainder}  # remainder has x2
    assert repo.ids(f"parents({remainder})") == {selected}           # selected is the parent


def test_abandon_reparents_descendants(repo):
    """``jj abandon`` removes a change; its descendants rebase onto its parent."""
    c1 = repo.commit("feat: c1", {"c1.txt": "1\n"})
    _c2 = repo.commit("feat: c2", {"c2.txt": "2\n"})
    c3 = repo.commit("feat: c3", {"c3.txt": "3\n"})
    repo.jj("abandon", _c2)
    assert repo.ids(f"parents({c3})") == {c1}          # c3 now sits on c1
    assert repo.ids(f"present({_c2})") == set()         # c2 is gone
    assert "3" == repo.jj_out("file", "show", "-r", c3, "c3.txt")  # content kept (jj_out strips)


def test_revert_creates_an_inverse_commit(repo):
    """``jj revert`` builds a NEW commit that inverts a target — no rewrite.

    This is the build-forward pattern for a pushed/immutable change.
    """
    c1 = repo.commit("feat: c1", {"c1.txt": "1\n"})
    repo.commit("feat: c2", {"c2.txt": "2\n"})
    repo.jj("revert", "-r", c1, "--insert-after", "@")

    rev = _one(repo, 'description(substring:"Revert")')
    # the revert removes c1.txt (inverts the add), and does not rewrite c1:
    assert repo.jj("file", "show", "-r", rev, "c1.txt", check=False).returncode != 0
    assert repo.ids(f"present({c1})") == {c1}          # original still there


def test_duplicate_copies_a_commit(repo):
    """``jj duplicate --onto`` copies a commit elsewhere (cherry-pick)."""
    anchor = repo.commit("feat: anchor", {"anchor.txt": "x\n"})
    d = _commit_on(repo, anchor, "feat: dup-me", {"dup.txt": "d\n"})
    base = _commit_on(repo, anchor, "feat: dest-base", {"base.txt": "b\n"})
    repo.jj("duplicate", d, "--onto", base)

    copies = repo.ids('description(substring:"dup-me")')
    assert len(copies) == 2                             # original + copy
    copy = next(iter(copies - {d}))
    assert repo.ids(f"{copy} & descendants({base})") == {copy}       # copy sits on base
    assert "d" == repo.jj_out("file", "show", "-r", copy, "dup.txt")  # same content (jj_out strips)


def test_simplify_parents_drops_a_redundant_edge(repo):
    """``jj simplify-parents`` removes a parent already reachable via another."""
    p = repo.commit("feat: p", {"p.txt": "p\n"})
    q = _commit_on(repo, p, "feat: q", {"q.txt": "q\n"})  # q descends from p
    repo.jj("new", p, q, "-m", "merge redundant")          # @ = merge(p, q); p is redundant
    m = repo.change_id("@")
    assert repo.ids(f"parents({m})") == {p, q}             # both parents before

    repo.jj("simplify-parents", "-r", m)
    assert repo.ids(f"parents({m})") == {q}                # p edge dropped
