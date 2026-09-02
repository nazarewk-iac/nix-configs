"""Amend / rework a commit — day-to-day, branch-agnostic golden paths.

These need no fork slot; they use ``JJConfig.without_slot()`` (the ``mkrepo``
default) and a plain linear history. See ``test_amend.md`` for the prose and the
edit-vs-squash-vs-describe decision.
"""

from __future__ import annotations


def _two_commit_repo(mkrepo):
    """Build ``c1 <- c2`` with ``@`` on ``c2`` (the tip, described, no trailing
    empty change). Returns (repo, c1, c2)."""
    repo = mkrepo()
    repo.write("a.txt", "1\n")
    repo.describe("feat: one")
    c1 = repo.change_id("@")
    repo.new()
    repo.write("b.txt", "2\n")
    repo.describe("feat: two")
    c2 = repo.change_id("@")
    return repo, c1, c2


def test_amend_in_place_with_jj_edit(mkrepo):
    """``jj edit <id>`` moves ``@`` into a commit; edits amend it directly.

    The change id is stable (only the content and commit id change), and the
    descendant is rebased automatically. ``jj new`` afterward leaves the tip.
    """
    repo, c1, c2 = _two_commit_repo(mkrepo)
    old_cid = repo.commit_id(c1)

    repo.jj("edit", c1)
    assert repo.change_id("@") == c1          # @ is now the commit itself
    repo.write("a.txt", "1-amended\n")
    repo.jj("status")                          # snapshot the edit into c1

    assert repo.jj_out("file", "show", "-r", c1, "a.txt") == "1-amended"
    assert repo.change_id("@") == c1           # change id stable across the amend
    assert repo.commit_id(c1) != old_cid       # but the commit was rewritten
    assert repo.ids(c2) == {c2}                # descendant preserved (same change id)

    repo.jj("new", c2)                         # leave a fresh empty @ on the tip
    assert repo.change_id("@") != c1


def test_amend_by_squash_into(mkrepo):
    """Accumulate a fixup in ``@``, then ``jj squash --into <id>`` folds it back.

    Use this when you did not want to sit inside the commit — you made the fixup
    on top and route it down to the earlier commit.
    """
    repo, c1, c2 = _two_commit_repo(mkrepo)
    repo.new()                                 # empty @ on top of c2
    repo.write("a.txt", "1-fixed\n")           # a fixup that belongs to c1
    repo.jj("squash", "--into", c1)

    assert repo.jj_out("file", "show", "-r", c1, "a.txt") == "1-fixed"
    assert repo.ids(c1) == {c1}                # c1 keeps its change id
    assert "a.txt" not in repo.jj_out("diff", "--name-only")  # @ no longer carries it


def test_reword_changes_message_only(mkrepo):
    """``jj describe -r <id>`` changes a commit's message, not its content, and
    does not move ``@``."""
    repo, c1, c2 = _two_commit_repo(mkrepo)
    before = repo.jj_out("file", "show", "-r", c1, "a.txt")

    repo.describe("feat: renamed one", rev=c1)

    assert repo.jj_out("log", "--no-graph", "-r", c1, "-T", "description.first_line()") \
        == "feat: renamed one"
    assert repo.jj_out("file", "show", "-r", c1, "a.txt") == before  # content unchanged
    assert repo.change_id("@") == c2           # @ did not move
