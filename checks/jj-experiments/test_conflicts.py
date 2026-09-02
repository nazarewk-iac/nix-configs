"""Conflict golden paths — detect and resolve, the agent-safe way.

Branch-agnostic (no fork slot). A fork-specific conflict-on-integration case lives
in test_rebase.py; this group is the general workflow. See test_conflicts.md.

jj records a conflict inside the commit instead of stopping the command. Detect it
with the ``conflicts()`` revset (or ``jj resolve --list``), inspect jj's conflict
markers, then resolve by writing the merged content and letting jj snapshot.
Never the interactive ``jj resolve`` picker in an agent — it hangs.
"""

from __future__ import annotations


def _diverge(repo):
    """Build base -> {X, Y} where X and Y edit the same line differently.

    Returns (base, x, y).
    """
    repo.write("conf.txt", "base\n")
    repo.describe("base")
    base = repo.change_id("@")

    repo.new(base)
    repo.write("conf.txt", "X-side\n")
    repo.describe("side X")
    x = repo.change_id("@")

    repo.new(base)
    repo.write("conf.txt", "Y-side\n")
    repo.describe("side Y")
    y = repo.change_id("@")
    return base, x, y


def test_merge_conflict_detect_inspect_and_resolve(mkrepo):
    repo = mkrepo()
    _, x, y = _diverge(repo)

    # Merging the two divergent sides conflicts; jj records it in the merge.
    merge = repo.new(x, y, message="chore: merge X and Y")
    assert repo.ids("conflicts()") == {merge}

    # `jj resolve --list` reports the conflicted file (run at the conflicted rev).
    listed = repo.jj_out("resolve", "--list", "-r", merge)
    assert "conf.txt" in listed

    # jj writes its own conflict markers (not classic git markers).
    shown = repo.jj_out("file", "show", "-r", merge, "conf.txt")
    assert "<<<<<<<" in shown
    assert "%%%%%%%" in shown
    assert ">>>>>>>" in shown

    # Resolve by writing the merged content; any jj command snapshots it.
    repo.write("conf.txt", "resolved\n")
    repo.jj("status")
    assert repo.ids("conflicts()") == set()
    assert (repo.path / "conf.txt").read_text() == "resolved\n"


def test_rebase_into_conflict_and_resolve(mkrepo):
    repo = mkrepo()
    _, x, y = _diverge(repo)

    # Rebasing X onto Y replays X's edit over Y's edit → X becomes conflicted.
    repo.jj("rebase", "-r", x, "-d", y)
    assert repo.ids("conflicts()") == {x}

    # Move @ onto the conflicted commit, write the resolution, snapshot.
    repo.jj("edit", x)
    repo.write("conf.txt", "resolved\n")
    repo.jj("status")
    assert repo.ids("conflicts()") == set()
    assert (repo.path / "conf.txt").read_text() == "resolved\n"


def test_resolve_list_reports_no_conflicts_when_clean(mkrepo):
    repo = mkrepo()
    repo.commit("feat: one", {"a.txt": "1\n"})
    # No conflicts anywhere.
    assert repo.ids("conflicts()") == set()
    r = repo.jj("resolve", "--list", check=False)
    # jj exits non-zero and says there is nothing to resolve.
    assert r.returncode != 0
    assert "No conflicts" in (r.stdout + r.stderr) or "no conflicts" in (r.stdout + r.stderr).lower()
