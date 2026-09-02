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
