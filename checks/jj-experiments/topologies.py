"""Reusable topology builders for the jj fork/branch use-case tests.

Each builder takes a fresh ``Repo`` (from the ``mkrepo`` fixture) and the fork
slot ``JJConfig`` (from ``harness.slot_config()``). It builds a known graph with
real bare ``upstream`` and ``fork`` remotes, then installs the fork aliases and
returns a ``labels`` dict that maps a node label to its change id. Tests assert
against those labels.

Build order matters: jj ``latest()`` (and the ``*-tip`` aliases) pick by commit
time, so the builders create nodes in a fixed order and the harness stamps each
with an increasing deterministic time.

The reference graph (from the revset-suite analysis):

    A ── P1 ── P2                (public upstream line; main@upstream = P2)
    │
    ├── U1 ── U2                 (local upstream line; upstream, upstream@fork = U2)
    │           \\
    │            M ── L1 ── L2 ── L3 ── @   (M = merge; main, main@fork = M)
    │           /
    └── F1                       (fork-sensitive; fork chain)

Expected classification: tree-merge={M}; upstream-incoming={P1,P2};
to-rebase={L1,L2,L3}; fork-direct={F1,L2}; upstream-safe={L1,L3};
fork-leaked={L2}; upstream-local={U1,U2}.
"""

from __future__ import annotations


def _node(repo, parents, message, files=None):
    """Create a described commit on ``parents`` and return its change id.

    ``@`` moves onto the new commit. Content is written before the describe, so
    the snapshot carries it. The harness stamps a deterministic increasing time.
    """
    repo.new(*parents)
    for relpath, content in (files or {}).items():
        repo.write(relpath, content)
    repo.describe(message)
    return repo.change_id("@")


def _push_rev_as(repo, remote, rev, remote_bookmark):
    """Push one revision to a differently-named remote bookmark via git.

    A jj bookmark has a single target, but the graph needs the remote bookmark
    ``main`` on the upstream remote to point at the public tip while the local
    ``main`` points at the merge. So push the git commit object directly, then
    import the remote ref back into jj.
    """
    sha = repo.jj_out("log", "--no-graph", "-r", rev, "-T", "commit_id")
    repo.git("push", remote, f"{sha}:refs/heads/{remote_bookmark}")
    repo.jj("git", "import")


def build_reference(repo, slot_cfg, *, push_main_fork: bool = True) -> dict:
    """Build the full reference graph. Return ``labels`` (label -> change id).

    With ``push_main_fork=True`` the merge is pushed to the fork remote, so
    ``main@fork`` exists, ``trunk()`` resolves to it, and the merge is frozen
    (``merge-frozen`` non-empty). With ``push_main_fork=False`` the merge stays
    local and mutable (``merge-frozen`` empty).

    The graph is built with a plain config (user only). The fork aliases are
    installed at the end, after the remotes and bookmarks exist, so a
    ``trunk()``/``immutable_heads()`` alias never names a missing ref mid-build.
    """
    labels = {}

    # A: root commit on the initial (empty) working copy.
    repo.write("README.md", "# repo\n")
    repo.describe("chore: readme")
    labels["A"] = repo.change_id("@")
    a = labels["A"]

    # Public upstream line off A (fetched, not merged into @).
    labels["P1"] = _node(repo, [a], "feat: public change 1", {"flake.lock": "v1\n"})
    labels["P2"] = _node(repo, [labels["P1"]], "feat: public change 2", {"flake.lock": "v2\n"})

    # Local upstream line off A (merged below the tree merge).
    labels["U1"] = _node(repo, [a], "feat: shared module", {"modules/shared.nix": "# u1\n"})
    labels["U2"] = _node(repo, [labels["U1"]], "feat: shared edit", {"modules/shared.nix": "# u2\n"})

    # Fork-sensitive change off A (path matches a denied pattern).
    labels["F1"] = _node(
        repo, [a], "feat: host wiring", {"hosts/PLACEHOLDER-SENSITIVE.nix": "# host\n"}
    )

    # The single fork merge.
    labels["M"] = _node(repo, [labels["U2"], labels["F1"]], "chore(merge): merge in upstream")

    # Local work above the merge: generic, fork-sensitive, generic.
    labels["L1"] = _node(repo, [labels["M"]], "feat: generic foo", {"modules/foo.nix": "# l1\n"})
    labels["L2"] = _node(
        repo,
        [labels["L1"]],
        "feat: PLACEHOLDER-SENSITIVE vpn",
        {"docs/notes.md": "host = PLACEHOLDER-SENSITIVE\n"},
    )
    labels["L3"] = _node(repo, [labels["L2"]], "feat: generic bar", {"modules/bar.nix": "# l3\n"})

    # Empty working copy on top of L3 (the resting single-parent @).
    repo.new(labels["L3"])
    labels["@"] = repo.change_id("@")

    # Remotes and bookmarks.
    repo.register_remote("upstream")
    repo.register_remote("fork")
    repo.bookmark_set("upstream", labels["U2"])
    repo.bookmark_set("main", labels["M"])

    # main@upstream = P2 (public tip). upstream@fork = U2. main@fork = M.
    _push_rev_as(repo, "upstream", labels["P2"], "main")
    repo.push("fork", "upstream")
    if push_main_fork:
        repo.push("fork", "main")

    # Now install the fork aliases; every ref they name already exists.
    repo.cfg = slot_cfg
    repo.apply_config()
    return labels


def build_base_tree(repo, slot_cfg) -> dict:
    """The frozen resting state: a published merge with an empty ``@`` on top.

    ``main@fork`` = the merge ``M`` (pushed, so it is immutable and the `fork`
    aliases classify correctly). ``upstream-tip`` = ``U2``, ``fork-tip`` = ``M``.
    ``merge-frozen`` = ``{M}``. Realistic starting point for the placement tests.

    Returns ``labels`` with A, U1, U2, F1, M, and ``@``.
    """
    labels = {}
    repo.write("README.md", "# repo\n")
    repo.describe("chore: readme")
    labels["A"] = repo.change_id("@")
    a = labels["A"]

    labels["U1"] = _node(repo, [a], "feat: shared module", {"modules/shared.nix": "# u1\n"})
    labels["U2"] = _node(repo, [labels["U1"]], "feat: shared edit", {"modules/shared.nix": "# u2\n"})
    labels["F1"] = _node(
        repo, [a], "feat: host wiring", {"hosts/PLACEHOLDER-SENSITIVE.nix": "# host\n"}
    )
    labels["M"] = _node(repo, [labels["U2"], labels["F1"]], "chore(merge): merge in upstream")

    repo.new(labels["M"])
    labels["@"] = repo.change_id("@")

    repo.register_remote("upstream")
    repo.register_remote("fork")
    repo.bookmark_set("upstream", labels["U2"])
    repo.bookmark_set("main", labels["M"])
    _push_rev_as(repo, "upstream", labels["U2"], "main")
    repo.push("fork", "upstream")
    repo.push("fork", "main")  # main@fork = M — always published in a real fork tree

    repo.cfg = slot_cfg
    repo.apply_config()
    return labels


def build_incoming_tree(repo, slot_cfg) -> dict:
    """Frozen base plus new upstream commits fetched but not merged.

    ``P1``, ``P2`` are children of ``U2`` on the public remote
    (``main@upstream`` = ``P2``), not in ``@``'s ancestry, so
    ``upstream-incoming`` = ``{P1, P2}``. ``@`` rests empty on the merge ``M``.
    ``upstream-tip`` = ``P2``, ``fork-tip`` = ``M``, ``merge-frozen`` = ``{M}``.
    This models "new upstream arrived; integrate it".

    Returns ``labels`` with A, U1, U2, F1, M, P1, P2, and ``@``.
    """
    labels = {}
    repo.write("README.md", "# repo\n")
    repo.describe("chore: readme")
    labels["A"] = repo.change_id("@")
    a = labels["A"]

    labels["U1"] = _node(repo, [a], "feat: shared module", {"modules/shared.nix": "# u1\n"})
    labels["U2"] = _node(repo, [labels["U1"]], "feat: shared edit", {"modules/shared.nix": "# u2\n"})
    labels["F1"] = _node(
        repo, [a], "feat: host wiring", {"hosts/PLACEHOLDER-SENSITIVE.nix": "# host\n"}
    )
    labels["M"] = _node(repo, [labels["U2"], labels["F1"]], "chore(merge): merge in upstream")

    repo.register_remote("upstream")
    repo.register_remote("fork")
    repo.bookmark_set("upstream", labels["U2"])
    repo.bookmark_set("main", labels["M"])
    _push_rev_as(repo, "upstream", labels["U2"], "main")  # main@upstream = U2 (last synced)
    repo.push("fork", "upstream")
    repo.push("fork", "main")  # upstream@fork = U2, main@fork = M (frozen)

    # New upstream arrives as children of U2 (fetched, not merged into @).
    labels["P1"] = _node(repo, [labels["U2"]], "feat: public one", {"flake.lock": "v1\n"})
    labels["P2"] = _node(repo, [labels["P1"]], "feat: public two", {"flake.lock": "v2\n"})
    _push_rev_as(repo, "upstream", labels["P2"], "main")  # main@upstream = P2 (advanced)

    repo.new(labels["M"])  # rest @ back on the merge
    labels["@"] = repo.change_id("@")

    repo.cfg = slot_cfg
    repo.apply_config()
    return labels


def build_mutable_incoming_tree(repo, slot_cfg) -> dict:
    """A published base merge (M0, frozen) with a mutable merge (M1) above it.

    ``main@fork`` = ``M0`` (a prior publish, so the fork aliases classify
    correctly and ``trunk()`` resolves), while the current merge ``M1`` is
    mutable. ``UL1`` is a local upstream commit that is not on the public remote,
    so ``upstream-local`` = ``{UL1}``. New upstream ``P1``, ``P2`` are fetched
    (``main@upstream`` = ``P2``), so ``upstream-incoming`` = ``{P1, P2}``.
    ``merge-frozen`` is empty (M1 is mutable). ``@`` rests empty on ``M1``.

    Returns ``labels`` with A, U1, F1, M0, UL1, M1, P1, P2, and ``@``.
    """
    labels = {}
    repo.write("README.md", "# repo\n")
    repo.describe("chore: readme")
    labels["A"] = repo.change_id("@")
    a = labels["A"]

    labels["U1"] = _node(repo, [a], "feat: shared module", {"modules/shared.nix": "# u1\n"})
    labels["F1"] = _node(
        repo, [a], "feat: host wiring", {"hosts/PLACEHOLDER-SENSITIVE.nix": "# host\n"}
    )
    labels["M0"] = _node(
        repo, [labels["U1"], labels["F1"]], "chore(upstream): merge (published)"
    )

    repo.register_remote("upstream")
    repo.register_remote("fork")
    repo.bookmark_set("upstream", labels["U1"])
    repo.bookmark_set("main", labels["M0"])
    _push_rev_as(repo, "upstream", labels["U1"], "main")  # main@upstream = U1
    repo.push("fork", "upstream")  # upstream@fork = U1
    repo.push("fork", "main")  # main@fork = M0 (frozen prior publish)

    # Local upstream work, not pushed to the public remote.
    labels["UL1"] = _node(repo, [labels["U1"]], "feat: local upstream fix", {"modules/local.nix": "# ul1\n"})
    # A new mutable merge folds the local upstream work over the published merge.
    labels["M1"] = _node(repo, [labels["UL1"], labels["M0"]], "chore(upstream): merge")

    # New upstream arrives as children of U1; the public remote advances.
    labels["P1"] = _node(repo, [labels["U1"]], "feat: public one", {"flake.lock": "v1\n"})
    labels["P2"] = _node(repo, [labels["P1"]], "feat: public two", {"flake.lock": "v2\n"})
    _push_rev_as(repo, "upstream", labels["P2"], "main")  # main@upstream = P2

    repo.new(labels["M1"])  # rest @ on the mutable merge
    labels["@"] = repo.change_id("@")

    repo.cfg = slot_cfg
    repo.apply_config()
    return labels


def build_conflict_tree(repo, slot_cfg) -> dict:
    """Frozen base where a local commit and new upstream edit the same file.

    ``U1`` writes ``conf.txt`` = ``base``. A local commit ``L`` above the merge
    changes it to ``local``; new upstream ``P1`` changes it to ``public``. So
    integrating ``L`` with ``P1`` produces a conflict on ``conf.txt``.
    ``fork-tip`` = ``L``, ``upstream-incoming-tip`` = ``P1``.

    Returns ``labels`` with A, U1, F1, M, L, P1, and ``@``.
    """
    labels = {}
    repo.write("README.md", "# repo\n")
    repo.describe("chore: readme")
    labels["A"] = repo.change_id("@")
    a = labels["A"]

    labels["U1"] = _node(repo, [a], "feat: shared conf", {"conf.txt": "base\n"})
    labels["F1"] = _node(
        repo, [a], "feat: host wiring", {"hosts/PLACEHOLDER-SENSITIVE.nix": "# host\n"}
    )
    labels["M"] = _node(repo, [labels["U1"], labels["F1"]], "chore(upstream): merge")

    repo.register_remote("upstream")
    repo.register_remote("fork")
    repo.bookmark_set("upstream", labels["U1"])
    repo.bookmark_set("main", labels["M"])
    _push_rev_as(repo, "upstream", labels["U1"], "main")
    repo.push("fork", "upstream")
    repo.push("fork", "main")  # main@fork = M (frozen)

    # A local change above the merge edits conf.txt.
    labels["L"] = _node(repo, [labels["M"]], "feat: local tweak", {"conf.txt": "local\n"})
    # New upstream edits the same file differently.
    labels["P1"] = _node(repo, [labels["U1"]], "feat: public tweak", {"conf.txt": "public\n"})
    _push_rev_as(repo, "upstream", labels["P1"], "main")  # main@upstream = P1

    repo.new(labels["L"])  # @ on the local commit (fork-tip)
    labels["@"] = repo.change_id("@")

    repo.cfg = slot_cfg
    repo.apply_config()
    return labels


def build_frozen_tree(repo, slot_cfg) -> dict:
    """Reference graph with the merge pushed to the fork remote (frozen)."""
    return build_reference(repo, slot_cfg, push_main_fork=True)


def build_mutable_tree(repo, slot_cfg) -> dict:
    """Reference graph with the merge left local and mutable."""
    return build_reference(repo, slot_cfg, push_main_fork=False)


def build_mixed_working_copy(repo, slot_cfg) -> dict:
    """Frozen tree, but ``@`` holds mixed generic + fork-sensitive content.

    Ready for a split-by-content case. ``@`` is undescribed and carries one
    generic file and one fork-sensitive file.
    """
    labels = build_reference(repo, slot_cfg, push_main_fork=True)
    repo.write("modules/generic.nix", "# generic work\n")
    repo.write("hosts/PLACEHOLDER-SENSITIVE-extra.nix", "# sensitive work\n")
    return labels


def build_branch_tree(repo) -> dict:
    """A long-lived local branch beside a shared trunk (no fork, no content split).

    One remote ``origin`` holds the trunk. The branch ``B1 -> B2`` sits on an
    earlier trunk base ``A`` while ``main@origin`` has advanced to new trunk
    commits ``T1 -> T2`` (fetched, not yet integrated). ``@`` rests empty on the
    branch tip.

    Branch-mode revset aliases are added as flag overlays AFTER ``main@origin``
    exists, so no alias names a missing ref during the build:

    - ``trunk()``            = ``main@origin`` (the shared trunk tip)
    - ``trunk-incoming``     = ``@..main@origin`` (fetched, not yet integrated)
    - ``trunk-incoming-tip`` = ``main@origin``
    - ``branch``             = ``trunk()..@ & ~description("")`` (local branch commits)
    - ``branch-tip``         = ``heads(branch)``

    So ``trunk-incoming`` = {T1, T2}; ``branch`` = {B1, B2}. The pushed trunk
    (A, T1, T2) is immutable; the branch (B1, B2) is mutable. This mirrors the
    fork's `upstream-incoming`/`upstream-incoming-tip` aliases minus the fork
    remote and the content split.

    No fork slot is needed (use ``mkrepo()`` with the default
    ``JJConfig.without_slot()``). Returns ``labels`` with A, B1, B2, T1, T2, @.
    """
    labels = {}
    repo.write("README.md", "# repo\n")
    repo.describe("chore: readme")
    labels["A"] = repo.change_id("@")
    a = labels["A"]

    # long-lived branch off A (local, mutable)
    labels["B1"] = _node(repo, [a], "feat: branch one", {"branch/b1.txt": "b1\n"})
    labels["B2"] = _node(repo, [labels["B1"]], "feat: branch two", {"branch/b2.txt": "b2\n"})

    # trunk advances off A and is published to origin (immutable once pushed)
    labels["T1"] = _node(repo, [a], "feat: trunk one", {"trunk/t1.txt": "t1\n"})
    labels["T2"] = _node(repo, [labels["T1"]], "feat: trunk two", {"trunk/t2.txt": "t2\n"})
    repo.register_remote("origin")
    _push_rev_as(repo, "origin", labels["T2"], "main")  # main@origin = T2

    repo.new(labels["B2"])  # rest @ empty on the branch tip
    labels["@"] = repo.change_id("@")

    # Branch-mode aliases: flag overlays, active from the next jj call. main@origin
    # exists now, so trunk()/immutable_heads() resolve without a missing-ref trap.
    repo.cfg.revset_alias("trunk()", "main@origin")
    repo.cfg.revset_alias("trunk-incoming", "@..main@origin")
    repo.cfg.revset_alias("trunk-incoming-tip", "main@origin")
    repo.cfg.revset_alias("branch", 'trunk()..@ & ~description("")')
    repo.cfg.revset_alias("branch-tip", "heads(branch)")
    return labels
