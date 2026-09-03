"""Long-lived-branch mode — the fork model minus the fork remote and content split.

A branch tracks a shared trunk (`main@origin`). New trunk commits arrive and get
integrated by rebase (linear) or by merge (the same shape as the fork's single
merge). These are branch-agnostic: no fork slot, no `fork-direct`/`fork-leaked`.

See `test_branch.md` for the prose and the fork <-> branch cross-check.
"""

from __future__ import annotations

import pytest

import topologies


@pytest.fixture
def branch(mkrepo):
    repo = mkrepo()
    labels = topologies.build_branch_tree(repo)
    return repo, labels


def _one(repo, revset):
    ids = repo.ids(revset)
    assert len(ids) == 1, f"{revset} -> {ids}"
    return next(iter(ids))


def test_branch_tree_shape(branch):
    repo, L = branch
    assert repo.ids("trunk-incoming") == {L["T1"], L["T2"]}
    assert repo.ids("trunk-incoming-tip") == {L["T2"]}
    assert repo.ids("branch") == {L["B1"], L["B2"]}
    assert repo.ids("branch-tip") == {L["B2"]}


def test_add_change_to_branch_is_a_plain_split(branch):
    """Add a change to the branch: a plain split on top. No dual-parent merge."""
    repo, L = branch
    repo.write("branch/b3.txt", "b3\n")
    repo.jj("split", "-m", "feat: branch three", "--", "branch/b3.txt")

    b3 = _one(repo, 'description(substring:"branch three")')
    assert repo.ids(f"parents({b3})") == {L["B2"]}   # single parent, no merge
    assert b3 in repo.ids("branch")
    assert repo.ids("branch-tip") == {b3}


def test_integrate_trunk_by_rebase(branch):
    """Integrate new trunk by rebasing the branch onto the new trunk tip (linear)."""
    repo, L = branch
    t2_cid = repo.commit_id(L["T2"])

    repo.jj("rebase", "-s", "roots(branch)", "-d", "trunk-incoming-tip")

    assert repo.ids(f'parents({L["B1"]})') == {L["T2"]}  # branch root now on the new trunk tip
    assert repo.ids("trunk-incoming") == set()           # all trunk integrated
    assert repo.commit_id(L["T2"]) == t2_cid             # pushed trunk not rewritten
    assert repo.ids("branch & merges()") == set()        # linear, no merge introduced


def test_integrate_trunk_by_merge(branch):
    """Integrate new trunk by merging it into the branch (fork-shaped, no rebase)."""
    repo, L = branch
    t2_cid = repo.commit_id(L["T2"])

    repo.jj("new", "branch-tip", "trunk-incoming-tip", "-m", "merge trunk")
    m = repo.change_id("@")

    assert repo.ids(f"parents({m})") == {L["B2"], L["T2"]}  # merge(branch tip, new trunk)
    assert repo.ids("trunk-incoming") == set()             # trunk integrated
    assert repo.commit_id(L["T2"]) == t2_cid               # pushed trunk not rewritten
    assert repo.ids(f'{L["T2"]} & ::@') == {L["T2"]}       # old trunk stays an ancestor


def test_upstream_only_fetch_then_rebase_onto_tip(mkrepo):
    """No branch, no fork: rebase local work onto the fetched upstream tip.

    Models docs/jujutsu-vcs.md "Without a fork (upstream-only)": one remote holds
    the trunk; after `jj git fetch`, `jj rebase -s <work> -d main@origin` keeps
    local work current. No fork slot, no content split.
    """
    repo = mkrepo()  # no slot needed
    a = repo.commit("chore: readme", {"README.md": "# repo\n"})
    repo.register_remote("origin")
    repo.bookmark_set("main", a)
    repo.push("origin", "main")                       # main@origin = A

    # local work built on the OLD base A
    work = repo.new(a, message="feat: local work")
    repo.write("w.txt", "w\n")

    # upstream advances: a new trunk commit, pushed straight to origin, then fetched
    up = repo.new(a, message="feat: upstream advance")
    repo.write("t.txt", "t\n")
    sha = repo.commit_id(up)
    repo.git("push", "origin", f"{sha}:refs/heads/main")
    repo.jj("git", "fetch", "--remote", "origin")

    assert repo.ids("main@origin") == {up}            # fetch advanced the tip
    assert repo.ids(f"parents({work})") == {a}        # work still on the old base

    repo.jj("rebase", "-s", work, "-d", "main@origin")
    assert repo.ids(f"parents({work})") == {up}       # work now on the fetched tip


def test_cannot_rewrite_a_pushed_trunk_commit(branch):
    """The pushed trunk is immutable — build forward instead of rewriting it."""
    repo, L = branch
    r = repo.jj("describe", "-r", L["T2"], "-m", "rewrite", check=False)
    assert r.returncode != 0
    assert "immutable" in r.stderr.lower()

    ok = repo.jj("new", L["T2"], "-m", "forward", check=False)  # build forward is allowed
    assert ok.returncode == 0
