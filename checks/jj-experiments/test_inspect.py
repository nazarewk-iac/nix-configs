"""Inspect / read golden paths — read the graph and files safely.

Branch-agnostic day-to-day reads. No fork slot. See ``test_inspect.md`` for the
prose. The theme: read any revision without a checkout, and stay
non-interactive (``--no-pager``, no editor).
"""

from __future__ import annotations

import pytest


@pytest.fixture
def hist(mkrepo):
    """Two described commits (c1 <- c2) with an empty ``@`` on top."""
    r = mkrepo()
    c1 = r.commit("c1: add a", {"a.txt": "a1\n"})
    c2 = r.commit("c2: add b, edit a", {"b.txt": "b1\n", "a.txt": "a2\n"})
    return r, c1, c2


def test_file_show_reads_a_file_at_a_revision(hist):
    """Read a file at any revision without a checkout (never ``jj edit`` to read)."""
    repo, c1, c2 = hist
    assert repo.jj_out("file", "show", "-r", c1, "a.txt") == "a1"
    assert repo.jj_out("file", "show", "-r", c2, "a.txt") == "a2"


def test_diff_of_a_commit_lists_changed_paths(hist):
    """``jj diff -r <id>`` shows one commit's change; ``--name-only``/``--stat`` summarize."""
    repo, c1, c2 = hist
    names = set(repo.jj_out("diff", "-r", c2, "--name-only").splitlines())
    assert names == {"a.txt", "b.txt"}
    assert "a.txt" in repo.jj_out("diff", "-r", c2, "--stat")


def test_diff_between_two_revisions(hist):
    """``jj diff --from X --to Y`` shows the change from X to Y."""
    repo, c1, c2 = hist
    names = set(repo.jj_out("diff", "--from", c1, "--to", c2, "--name-only").splitlines())
    assert names == {"a.txt", "b.txt"}


def test_status_has_no_revision_flag_use_diff_instead(hist):
    """``jj status`` shows only the working copy; it takes no ``-r``.

    To inspect another revision use ``jj diff -r``/``jj show`` (verified: ``jj
    st -r`` errors in this jj version).
    """
    repo, c1, c2 = hist
    bad = repo.jj("status", "-r", c2, check=False)
    assert bad.returncode != 0
    assert "-r" in bad.stderr  # jj rejects the flag
    assert repo.jj("status").returncode == 0  # plain status works


def test_show_displays_a_commit(hist):
    """``jj show <rev>`` prints a commit's metadata and its diff."""
    repo, c1, c2 = hist
    out = repo.jj_out("show", c2)
    assert "c2: add b, edit a" in out
    assert "b.txt" in out


def test_log_template_reads_the_graph_non_interactively(hist):
    """``jj log --no-pager -r <revset> -T <template>`` reads fields without a pager."""
    repo, c1, c2 = hist
    assert repo.jj_out(
        "log", "--no-graph", "-r", c2, "-T", "description.first_line()"
    ) == "c2: add b, edit a"
    described = repo.ids("::@ & ~empty() & ~root()")
    assert {c1, c2} <= described
