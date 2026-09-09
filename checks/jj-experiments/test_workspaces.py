"""jj workspaces as the isolation mechanism for parallel agent work.

Prose and the reason for each case: ``test_workspaces.md``.

A ``git worktree`` is forbidden in the real repo. It is colocated: it registers
under the repo's own ``.git/worktrees/``, it has no ``.jj`` of its own, and it
shares one working-copy commit with the trunk checkout. Two writers then race
the same snapshot. ``jj workspace add`` is the replacement. These tests prove
the isolation properties the replacement depends on, and the three hazards that
need a written rule.
"""

from __future__ import annotations

import concurrent.futures
import re
import shutil

import topologies


# --- 1. structural isolation ------------------------------------------------


def test_workspace_has_own_jj_and_no_git(mkrepo):
    """A workspace holds its own ``.jj``, no ``.git``, and no git worktree entry."""
    repo = mkrepo()
    repo.commit("feat: base", {"a.nix": "1\n"})
    ws = repo.workspace_add("slot")

    # Own working-copy state, not a pointer into the trunk's .jj/working_copy.
    assert (ws.path / ".jj" / "working_copy").is_dir()
    # `.jj/repo` is a plain text file. It holds a relative path to the shared
    # store, resolved against the workspace's own `.jj` dir.
    repo_pointer = ws.path / ".jj" / "repo"
    assert repo_pointer.is_file()
    target = (ws.path / ".jj" / repo_pointer.read_text().strip()).resolve()
    assert target == (repo.path / ".jj" / "repo").resolve()

    # No .git at all. This is hazard 2: `git+file:.` and the git-hooks install
    # both need a .git, so neither works from a workspace.
    assert not (ws.path / ".git").exists()

    # The git worktree registry stays empty. This is the exact difference from
    # `git worktree`, which writes an entry here and shares the working copy.
    worktrees = repo.path / ".git" / "worktrees"
    assert not worktrees.exists() or not list(worktrees.iterdir())


def test_workspace_sits_outside_the_repo_tree(mkrepo):
    """The workspace dir is a sibling of the repo dir, named ``.<repo>--<slug>``."""
    repo = mkrepo("nix-configs")
    repo.commit("feat: base", {"a.nix": "1\n"})
    ws = repo.workspace_add("ssh-scoping")

    assert ws.path.parent == repo.path.parent
    assert ws.path.name == ".nix-configs--ssh-scoping"
    assert repo.path not in ws.path.parents
    # A leading-dot name forces the explicit --name flag; the recorded name is
    # the clean slug, not the dotted basename.
    assert set(repo.workspace_list()) == {"default", "ssh-scoping"}


def test_workspace_change_id_differs_from_trunk(mkrepo):
    """Each workspace owns a distinct ``@``, and the two are siblings."""
    repo = mkrepo()
    base = repo.commit("feat: base", {"a.nix": "1\n"})
    ws = repo.workspace_add("slot")

    assert repo.change_id("@") != ws.change_id("@")
    # Both new commits are children of the same base, so neither rewrites the
    # other's history.
    assert repo.ids("@-") == {base}
    assert ws.ids("@-") == {base}

    listed = repo.workspace_list()
    assert listed["default"] == repo.change_id("@")
    assert listed["slot"] == ws.change_id("@")


def test_workspace_add_accepts_a_base_revision(mkrepo):
    """``-r`` puts the workspace ``@`` on a chosen base, not on the trunk's ``@-``."""
    repo = mkrepo()
    first = repo.commit("feat: first", {"a.nix": "1\n"})
    second = repo.commit("feat: second", {"b.nix": "2\n"})

    ws = repo.workspace_add("slot", revision=first)
    assert ws.ids("@-") == {first}
    assert second not in ws.ids("::@")


def test_nested_dir_resolves_to_the_enclosing_workspace(mkrepo):
    """jj resolves the workspace from the current dir, never from the trunk."""
    repo = mkrepo()
    repo.commit("feat: base", {"a.nix": "1\n"})
    ws = repo.workspace_add("slot")

    deep = ws.path / "sub" / "deep"
    deep.mkdir(parents=True)
    assert ws.workspace_root(cwd=deep) == ws.path
    assert repo.workspace_root() == repo.path
    # `jj status` from the nested dir reports the workspace's own @.
    assert ws.change_id("@") == ws.jj_out(
        "log", "--no-graph", "-r", "@", "-T", "change_id.shortest(12)", cwd=deep
    )


def test_untracked_file_does_not_travel_into_a_workspace(mkrepo):
    """A fresh workspace holds tracked files only. Every ignored file is absent."""
    repo = mkrepo()
    repo.commit("feat: base", {"a.nix": "1\n"})
    repo.write(".gitignore", "/local.nix\n")
    repo.write("local.nix", "{ }\n")
    repo.jj("status")  # snapshot, so .gitignore is tracked in @

    ws = repo.workspace_add("slot")
    assert (ws.path / "a.nix").is_file()
    # This is hazard 3: `devenv.slots.local.nix` is git-ignored, so a workspace
    # never gets it. An agent must copy it before any devenv work.
    assert not (ws.path / "local.nix").exists()


# --- 2. concurrent writes ---------------------------------------------------


def test_concurrent_snapshots_do_not_lose_content(mkrepo):
    """Two workspaces snapshot at the same time with no truncation and no loss.

    This is the case the 2026-07-29 data loss failed. A ``git worktree`` shares
    one working-copy commit, so two snapshots race one file set. Two jj
    workspaces hold two working-copy commits, so they do not.
    """
    repo = mkrepo()
    repo.commit("feat: base", {"a.nix": "1\n"})
    ws = repo.workspace_add("slot")

    rounds = 15
    payload = "x" * 4096
    trunk_change = repo.change_id("@")
    ws_change = ws.change_id("@")
    problems: list[str] = []

    def churn(handle, label: str):
        for i in range(rounds):
            content = f"{label} {i}\n{payload}\n"
            handle.write(f"{label}.nix", content)
            result = handle.jj("status", check=False)
            if result.returncode != 0:
                problems.append(f"{label} {i} status rc={result.returncode}: {result.stderr}")
            read_back = (handle.path / f"{label}.nix").read_text()
            if read_back != content:
                problems.append(f"{label} {i} truncated: {len(read_back)} of {len(content)} bytes")

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [
            pool.submit(churn, repo, "trunk"),
            pool.submit(churn, ws, "slot"),
        ]
        for future in futures:
            future.result()

    assert problems == []
    # Neither working copy adopted the other's file.
    assert not (repo.path / "slot.nix").exists()
    assert not (ws.path / "trunk.nix").exists()
    # No commit was rewritten into a divergent pair by the race.
    assert repo.ids("divergent()") == set()
    assert repo.change_id("@") == trunk_change
    assert ws.change_id("@") == ws_change


def test_concurrent_commits_land_in_separate_changes(mkrepo):
    """Parallel commits from two workspaces both survive in the shared store."""
    repo = mkrepo()
    repo.commit("feat: base", {"a.nix": "1\n"})
    ws = repo.workspace_add("slot")

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        trunk_future = pool.submit(repo.commit, "feat: trunk work", {"trunk.nix": "t\n"})
        ws_future = pool.submit(ws.commit, "feat: slot work", {"slot.nix": "s\n"})
        trunk_change = trunk_future.result()
        ws_change = ws_future.result()

    assert trunk_change != ws_change
    # jj reconciles the concurrent operations; both commits are reachable.
    descriptions = repo.jj_out(
        "log", "--no-graph", "-r", "all()", "-T", 'description.first_line() ++ "\\n"'
    )
    assert "feat: trunk work" in descriptions
    assert "feat: slot work" in descriptions
    assert repo.ids("divergent()") == set()


# --- 3. lifecycle -----------------------------------------------------------


def test_forget_then_remove_directory(mkrepo):
    """``jj workspace forget`` drops the record; the dir removal is a second step."""
    repo = mkrepo()
    repo.commit("feat: base", {"a.nix": "1\n"})
    ws = repo.workspace_add("slot")

    repo.workspace_forget("slot")
    assert set(repo.workspace_list()) == {"default"}
    # forget leaves the files behind on purpose.
    assert ws.path.is_dir()

    shutil.rmtree(ws.path)
    assert set(repo.workspace_list()) == {"default"}


def test_remove_directory_then_forget(mkrepo):
    """The reverse order also works: delete the dir first, then forget the name."""
    repo = mkrepo()
    repo.commit("feat: base", {"a.nix": "1\n"})
    ws = repo.workspace_add("slot")

    shutil.rmtree(ws.path)
    # The trunk keeps working with a dangling workspace record.
    assert repo.jj("status", check=False).returncode == 0
    assert set(repo.workspace_list()) == {"default", "slot"}

    repo.workspace_forget("slot")
    assert set(repo.workspace_list()) == {"default"}


def test_op_restore_makes_another_workspace_stale(mkrepo):
    """A repo-wide op-log rewind is the one thing that needs ``update-stale``."""
    repo = mkrepo()
    repo.commit("feat: base", {"a.nix": "1\n"})
    ws = repo.workspace_add("slot")

    before = repo.op_id()
    ws.write("slot.nix", "s\n")
    ws.describe("feat: slot work")

    # A repo-wide operation from the trunk rewinds the shared op log below the
    # workspace's recorded working-copy operation.
    repo.jj("op", "restore", before)

    stale = ws.jj("status", check=False)
    assert stale.returncode != 0
    assert "stale" in stale.stderr.lower()

    ws.jj("workspace", "update-stale")
    assert ws.jj("status", check=False).returncode == 0


# --- 4. shared vs per-workspace config -------------------------------------


def test_repo_config_is_shared_and_workspace_config_is_not(mkrepo):
    """``--repo`` resolves to one shared file; ``--workspace`` is per workspace.

    This is hazard 1. ``modules/slots/jj/default.nix`` writes a symlink over the
    ``--repo`` path on every ``enterShell``. A devenv shell in a workspace
    therefore rewrites the trunk's repo config too.
    """
    repo = mkrepo()
    repo.commit("feat: base", {"a.nix": "1\n"})
    ws = repo.workspace_add("slot")

    assert repo.jj_out("config", "path", "--repo") == ws.jj_out("config", "path", "--repo")
    assert repo.jj_out("config", "path", "--workspace") != ws.jj_out("config", "path", "--workspace")

    # A repo-scope write from the workspace is visible in the trunk at once.
    ws.jj("config", "set", "--repo", "ui.default-command", '"log"')
    assert repo.jj_out("config", "get", "ui.default-command") == "log"

    # A workspace-scope write is not.
    ws.jj("config", "set", "--workspace", "ui.default-command", '"status"')
    assert ws.jj_out("config", "get", "ui.default-command") == "status"
    assert repo.jj_out("config", "get", "ui.default-command") == "log"


def test_repo_config_overwrite_from_workspace_strips_trunk_aliases(mkrepo):
    """Overwriting the shared ``--repo`` file removes an alias from the trunk.

    The slot's ``ln -sfn`` is exactly this overwrite. The test reproduces the
    silent failure the mandatory bootstrap step prevents.
    """
    repo = mkrepo()
    repo.commit("feat: base", {"a.nix": "1\n"})
    repo.jj("config", "set", "--repo", "revset-aliases.'fork-mark'", '"@"')
    assert repo.jj_out("config", "get", "revset-aliases.'fork-mark'") == "@"

    ws = repo.workspace_add("slot")
    shared = ws.jj_out("config", "path", "--repo")
    # A devenv shell in a workspace with no local slot settings writes a stub.
    with open(shared, "w") as handle:
        handle.write('[ui]\npaginate = "never"\n')

    gone = repo.jj("config", "get", "revset-aliases.'fork-mark'", check=False)
    assert gone.returncode != 0


# --- 5. fork revset aliases from a workspace -------------------------------


def test_fork_revset_aliases_resolve_from_a_workspace(mkrepo, harness):
    """``fork-tip`` and ``upstream-tip`` give the same answer in every workspace."""
    slot = harness.slot_config()
    repo = mkrepo(cfg=slot)
    labels = topologies.build_base_tree(repo, slot)

    ws = repo.workspace_add("slot")

    for alias in ("fork-tip", "upstream-tip"):
        from_trunk = repo.ids(alias)
        from_ws = ws.ids(alias)
        assert from_trunk, f"{alias} resolved to nothing in the trunk"
        assert from_trunk == from_ws, f"{alias} differs: {from_trunk} vs {from_ws}"

    # The topology labels still hold from the workspace.
    assert ws.ids("upstream-tip") == {labels["U2"]}
    assert ws.ids("fork-tip") == {labels["M"]}


def test_workspace_add_does_not_move_the_fork_tips(mkrepo, harness):
    """Adding a workspace leaves both tips where they were."""
    slot = harness.slot_config()
    repo = mkrepo(cfg=slot)
    topologies.build_base_tree(repo, slot)

    before = (repo.ids("fork-tip"), repo.ids("upstream-tip"))
    repo.workspace_add("slot")
    after = (repo.ids("fork-tip"), repo.ids("upstream-tip"))
    assert before == after


# --- 6. the workspace name in jj output ------------------------------------


def test_workspace_list_reports_every_workspace(mkrepo):
    """Three workspaces are all listed, each with its own change id."""
    repo = mkrepo()
    repo.commit("feat: base", {"a.nix": "1\n"})
    names = ["ssh-scoping", "flake-update", "docs-pass"]
    handles = {name: repo.workspace_add(name) for name in names}

    listed = repo.workspace_list()
    assert set(listed) == {"default", *names}
    # Every change id is distinct, so no two agents share a working copy.
    assert len(set(listed.values())) == len(listed)
    for name, handle in handles.items():
        assert listed[name] == handle.change_id("@")
        assert re.fullmatch(r"[k-z]{12}", listed[name])
