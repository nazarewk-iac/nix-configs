"""Discard / recover golden paths — jj restore, undo, and the operation log.

Branch-agnostic (no fork slot): every test uses ``mkrepo()`` with the default
``JJConfig.without_slot()`` and a plain linear history. See ``test_recover.md``
for the prose.
"""

from __future__ import annotations


def _read(repo, name: str) -> str:
    return (repo.path / name).read_text()


def _exists(repo, name: str) -> bool:
    return (repo.path / name).exists()


def test_restore_reverts_a_file_and_keeps_other_changes(mkrepo):
    """``jj restore <path>`` reverts one file in ``@`` to its parent content."""
    repo = mkrepo()
    repo.commit("feat: base", {"a.txt": "a1\n", "b.txt": "b1\n"})
    # @ edits a.txt and adds c.txt
    repo.write("a.txt", "a2\n")
    repo.write("c.txt", "c1\n")

    repo.jj("restore", "a.txt")

    assert _read(repo, "a.txt") == "a1\n"   # reverted to the parent's content
    assert _read(repo, "c.txt") == "c1\n"   # the unrelated change stays


def test_restore_from_a_revision(mkrepo):
    """``jj restore --from <rev> <path>`` brings a file back from a revision."""
    repo = mkrepo()
    v1 = repo.commit("feat: v1", {"cfg.txt": "one\n"})
    repo.commit("feat: v2", {"cfg.txt": "two\n"})  # @ is empty on v2

    repo.jj("restore", "--from", v1, "cfg.txt")

    assert _read(repo, "cfg.txt") == "one\n"


def test_abandon_reparents_descendants(mkrepo):
    """``jj abandon <id>`` drops a commit; its descendants rebase onto its parent."""
    repo = mkrepo()
    c1 = repo.commit("feat: c1", {"a.txt": "1\n"})
    c2 = repo.commit("feat: c2", {"b.txt": "2\n"})
    c3 = repo.commit("feat: c3", {"c.txt": "3\n"})

    repo.jj("abandon", c2)

    assert repo.ids(f"present({c2})") == set()   # c2 is gone
    assert repo.ids(f"parents({c3})") == {c1}     # c3 reparented onto c1
    assert _read(repo, "c.txt") == "3\n"          # c3's own change is preserved
    assert not _exists(repo, "b.txt")             # c2's change is gone


def test_undo_reverses_the_last_operation(mkrepo):
    """``jj undo`` reverses the single last operation (safe escape hatch)."""
    repo = mkrepo()
    repo.commit("feat: c1", {"a.txt": "1\n"})
    c2 = repo.commit("feat: c2", {"b.txt": "2\n"})

    repo.jj("abandon", c2)
    assert repo.ids(f"present({c2})") == set()

    repo.jj("undo")
    assert repo.ids(f"present({c2})") == {c2}   # c2 is back


def test_op_restore_rolls_back_multiple_operations(mkrepo):
    """``jj op restore <op>`` rolls the whole repo back to a chosen operation."""
    repo = mkrepo()
    repo.commit("feat: c1", {"a.txt": "1\n"})
    c2 = repo.commit("feat: c2", {"b.txt": "2\n"})
    c3 = repo.commit("feat: c3", {"c.txt": "3\n"})

    # the operation id for the current, known-good state:
    op0 = repo.jj_out("op", "log", "--no-graph", "--limit", "1", "-T", "self.id().short()")

    repo.jj("abandon", c3)
    repo.jj("abandon", c2)
    assert repo.ids(f"present({c2})") == set()
    assert repo.ids(f"present({c3})") == set()

    repo.jj("op", "restore", op0)   # roll back both abandons at once
    assert repo.ids(f"present({c2})") == {c2}
    assert repo.ids(f"present({c3})") == {c3}


def test_restore_discards_all_working_copy_changes(mkrepo):
    """``jj restore`` (no path) resets ``@`` to its parent — discard everything."""
    repo = mkrepo()
    repo.commit("feat: base", {"a.txt": "a1\n"})
    repo.write("a.txt", "changed\n")
    repo.write("new.txt", "x\n")

    repo.jj("restore")

    assert _read(repo, "a.txt") == "a1\n"
    assert not _exists(repo, "new.txt")
    assert "no changes" in repo.jj_out("st").lower()   # @ is empty vs its parent
