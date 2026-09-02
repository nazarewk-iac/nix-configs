"""Bookmarks, sync, and untrack — day-to-day golden paths.

Branch-agnostic (no fork slot): every test uses a plain repo from ``mkrepo``.
See ``test_bookmarks.md`` for the prose.
"""

from __future__ import annotations


def test_bookmark_create_set_delete(mkrepo):
    """Create a bookmark, move it, and delete it.

    A forward move is allowed; a backward or sideways move needs
    ``--allow-backwards``.
    """
    repo = mkrepo()
    c1 = repo.commit("feat: one", {"a.txt": "1\n"})
    c2 = repo.commit("feat: two", {"b.txt": "2\n"})

    repo.jj("bookmark", "create", "feat", "-r", c1)
    assert repo.ids("feat") == {c1}

    repo.jj("bookmark", "set", "feat", "-r", c2)  # forward move: allowed
    assert repo.ids("feat") == {c2}

    backward = repo.jj("bookmark", "set", "feat", "-r", c1, check=False)  # refused
    assert backward.returncode != 0
    assert "backwards" in backward.stderr.lower()

    repo.jj("bookmark", "set", "feat", "-r", c1, "--allow-backwards")  # now allowed
    assert repo.ids("feat") == {c1}

    repo.jj("bookmark", "delete", "feat")
    assert repo.ids("present(feat)") == set()


def test_push_then_fetch_between_two_repos(mkrepo):
    """Push a bookmark to a bare remote; a second repo fetches and builds on it.

    Headless bare push/fetch, no auth. This is the sync building block.
    """
    a = mkrepo("a")
    bare = a.register_remote("origin")
    base = a.commit("feat: base", {"a.txt": "1\n"})
    a.bookmark_set("main", base)
    a.push("origin", "main")

    b = mkrepo("b")
    b.register_remote("origin", bare)
    b.fetch("origin")

    assert b.ids('remote_bookmarks(remote="origin")') == {base}  # the pushed tip appears
    listing = b.jj_out("bookmark", "list", "--all-remotes")       # lists local + remote bookmarks
    assert "main@origin" in listing                               # the remote-tracking bookmark shows
    b.jj("new", "main@origin")                                    # bring @ onto it
    assert b.ids('main@origin & ::@') == {base}                   # now an ancestor of @


def test_untrack_needs_gitignore_first(mkrepo):
    """``jj file untrack`` refuses a non-ignored path; ignore it, then untrack.

    A path that is not ignored would be added back by the next command, so jj
    refuses. Add it to ``.gitignore`` first.
    """
    repo = mkrepo()
    repo.write("secret.local", "x\n")
    repo.write("keep.txt", "k\n")
    repo.describe("feat: add files")

    refused = repo.jj("file", "untrack", "secret.local", check=False)
    assert refused.returncode != 0
    assert "not ignored" in refused.stderr.lower()

    repo.write(".gitignore", "secret.local\n")
    repo.jj("file", "untrack", "secret.local")

    tracked = repo.jj_out("file", "list", "-r", "@").split()
    assert "secret.local" not in tracked
    assert "keep.txt" in tracked
