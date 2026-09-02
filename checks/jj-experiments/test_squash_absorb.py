"""Day-to-day: move working-copy edits into earlier commits — squash vs absorb.

Branch-agnostic (no fork slot). ``jj squash --from @ --into <id> -- <files>``
routes chosen files to a chosen commit; ``jj absorb`` auto-routes each hunk to
the ancestor that last touched those lines. See ``test_squash_absorb.md``.
"""

from __future__ import annotations


def _names(repo, rev):
    out = repo.jj_out("diff", "-r", rev, "--name-only")
    return {line for line in out.splitlines() if line}


def test_squash_from_into_routes_chosen_files(mkrepo):
    """``jj squash --from @ --into <id> -- <files>`` folds only those files.

    The target commit gains the content; the rest stays in ``@``.
    """
    repo = mkrepo()
    a = repo.commit("A adds a", {"a.txt": "a1\n"})  # @ is now an empty child of A
    repo.write("a.txt", "a1\na2\n")   # modify A's file
    repo.write("c.txt", "new\n")      # unrelated new file

    repo.jj("squash", "--from", "@", "--into", a, "--", "a.txt")

    assert "a2" in repo.jj_out("file", "show", "-r", a, "a.txt")  # folded into A
    assert _names(repo, "@") == {"c.txt"}                          # the rest stays in @


def test_absorb_routes_each_hunk_to_its_last_toucher(mkrepo):
    """``jj absorb`` sends each changed hunk to the ancestor that last touched it.

    A hunk with no clear ancestor (a brand-new file) stays in ``@``.
    """
    repo = mkrepo()
    a = repo.commit("A adds a", {"a.txt": "a1\n"})
    b = repo.commit("B adds b", {"b.txt": "b1\n"})
    repo.write("a.txt", "a1\na2\n")   # last touched by A
    repo.write("b.txt", "b1\nb2\n")   # last touched by B
    repo.write("c.txt", "new\n")      # no ancestor touched it

    repo.jj("absorb")

    assert "a2" in repo.jj_out("file", "show", "-r", a, "a.txt")  # routed to A
    assert "b2" in repo.jj_out("file", "show", "-r", b, "b.txt")  # routed to B
    assert _names(repo, "@") == {"c.txt"}                          # no-ancestor hunk stays in @


def test_absorb_does_not_move_into_an_immutable_ancestor(mkrepo):
    """``jj absorb`` refuses to move a hunk into an immutable ancestor.

    It leaves the change in ``@`` instead of rewriting published history.
    """
    repo = mkrepo()
    a = repo.commit("A adds a", {"a.txt": "a1\n"})
    a_cid = repo.commit_id(a)

    # make A immutable
    repo.bookmark_set("frozenA", a)
    repo.define_config("repo", 'revset-aliases."immutable_heads()"', "present(frozenA)")
    assert a in repo.ids("immutable()")

    repo.write("a.txt", "a1\na2\n")   # last touched by the now-immutable A
    repo.jj("absorb")

    assert "a.txt" in _names(repo, "@")            # left in @, not absorbed
    assert repo.commit_id(a) == a_cid              # A not rewritten
