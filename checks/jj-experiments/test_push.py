"""Push a change to a branch or fork — golden paths.

Branch-agnostic (no fork slot): every test uses plain repos from ``mkrepo`` and
bare remotes. See ``test_push.md`` for the prose and the "how to add a group"
walkthrough.

The four-step golden path each test shows::

    jj git fetch --remote=<remote>            # 1. see the real remote state
    jj rebase -b @ -d <branch>@<remote>       # 2. move your work onto the incoming tip (skip if ahead)
    jj bookmark set <branch> -r <your-rev>    # 3. point the branch at your work
    jj git push --remote=<remote> -b <branch> # 4. publish

The "remote moved ahead" cases use the two-repos-share-one-bare trick: repo ``b``
tracks and advances ``main`` on the same bare that repo ``a`` pushed to, then
``a`` fetches and is behind.

Verified jj-0.44 facts these tests pin down (they differ from first guesses):

- There is **no** ``--allow-new`` flag. A new named bookmark pushes directly and
  starts tracking.
- After ``jj git fetch``, a remote bookmark arrives **untracked**; a second repo
  must ``jj bookmark track <name>@<remote>`` before its push can move the branch.
- Approach A (rebasing the fetched commit *under* your work with
  ``--insert-before``) is refused only when the target is immutable: the trunk
  ``main@<remote>`` (always, even when tracked), or an **untracked** remote
  bookmark. It **succeeds** for a **tracked, non-trunk feature branch** (track it
  first). For the primary branch you cannot move the incoming — move your own
  mutable work instead (Approach B).
- ``jj git push`` is force-with-lease: a push made **before** fetching a moved
  remote is **rejected** ("stale info"); only **after** you fetch does a bare push
  of a non-descendant clobber the remote sideways. Rebase onto the incoming first
  so the push fast-forwards. Push a feature/PR branch to avoid touching the
  primary at all.
"""

from __future__ import annotations


def _origin_with_main(mkrepo):
    """Make repo ``a`` with a pushed ``main`` on a base commit.

    Returns ``(a, bare, base)``. ``a`` has ``origin`` registered, ``main`` set to
    the base commit and pushed (so ``main`` tracks ``main@origin``), and an empty
    ``@`` on top of the base.
    """
    a = mkrepo("a")
    bare = a.register_remote("origin")
    base = a.commit("feat: base", {"base.txt": "0\n"})
    a.bookmark_set("main", base)
    a.push("origin", "main")
    return a, bare, base


def _advance_remote(mkrepo, bare, message, files):
    """From a second repo sharing ``bare``, move ``main`` ahead by one commit.

    The second repo tracks ``main@origin`` first — a fetched bookmark is untracked,
    so without tracking its push is a no-op.
    """
    b = mkrepo("b")
    b.register_remote("origin", bare)
    b.fetch("origin")
    b.jj("bookmark", "track", "main@origin")
    b.jj("new", "main")
    moved = b.commit(message, files)
    b.bookmark_set("main", moved)
    b.push("origin", "main")
    return moved


def _push_feature(mkrepo, bare, name, message, files):
    """From a second repo sharing ``bare``, create and push a feature branch.

    Returns the pushed tip. The branch is a **non-trunk** remote bookmark, so a
    repo that fetches it can track it and treat it as mutable.
    """
    b = mkrepo("bf")
    b.register_remote("origin", bare)
    b.fetch("origin")
    b.jj("bookmark", "track", "main@origin")
    b.jj("new", "main")
    tip = b.commit(message, files)
    b.jj("bookmark", "create", name, "-r", tip)
    b.jj("git", "push", "--remote", "origin", "-b", name)
    return tip


def test_publish_anonymous_pr_branch(mkrepo):
    """Publish one change as an anonymous branch for a PR — the usual case.

    Golden path: ``jj git push -c <rev>``. jj creates an auto-named
    ``push-<change-id-prefix>`` bookmark and pushes it. No branch name needed.
    """
    a, _, base = _origin_with_main(mkrepo)
    work = a.commit("feat: my change", {"change.txt": "1\n"})

    a.jj("git", "push", "--remote", "origin", "-c", work)

    names = a.jj_out("bookmark", "list").splitlines()
    pushed = [n.split(":")[0].strip() for n in names if n.strip().startswith("push-")]
    assert pushed, f"expected a push-* bookmark, got: {names}"
    bm = pushed[0]
    assert a.ids(f"{bm}@origin") == {work}  # published at the change


def test_publish_named_branch_tracks_no_allow_new(mkrepo):
    """Publish a named branch — no ``--allow-new`` flag exists in jj 0.44.

    Golden path: ``jj bookmark create <name>`` then ``jj git push -b <name>``. The
    push creates the remote bookmark and starts tracking it, so a later push of
    the same branch just works.
    """
    a, _, base = _origin_with_main(mkrepo)
    work = a.commit("feat: work", {"work.txt": "1\n"})
    a.jj("bookmark", "create", "feature", "-r", work)

    a.jj("git", "push", "--remote", "origin", "-b", "feature")
    assert a.ids("feature@origin") == {work}

    work2 = a.commit("feat: more", {"more.txt": "2\n"})
    a.bookmark_set("feature", work2)
    a.jj("git", "push", "--remote", "origin", "-b", "feature")  # now tracked
    assert a.ids("feature@origin") == {work2}


def test_fast_forward_update(mkrepo):
    """Local work descends from ``main@origin`` — no rebase needed.

    Golden path: fetch (no remote change), set the bookmark, push.
    """
    a, _, base = _origin_with_main(mkrepo)
    work = a.commit("feat: ahead", {"ahead.txt": "1\n"})
    a.fetch("origin")  # remote unchanged

    a.bookmark_set("main", work)
    a.push("origin", "main")
    assert a.ids("main@origin") == {work}


def test_behind_whole_stack_rebase_b(mkrepo):
    """Remote moved; rebase your whole local stack onto it (Approach B, ``-b``).

    Golden path: fetch, ``jj rebase -b @ -d main@origin``, set, push.

    The real guard this pins down: ``jj git push`` is force-with-lease. A push
    made **before** fetching the moved remote is **rejected** with "stale info" —
    that is the safety net. Only **after** you fetch does a bare push of a
    non-descendant stop failing and instead move the bookmark **sideways**,
    discarding the remote's commit. So the discipline is: fetch, then rebase onto
    the incoming tip, so the push is a clean fast-forward, not a sideways clobber.
    """
    a, bare, base = _origin_with_main(mkrepo)
    c1 = a.commit("feat: c1", {"c1.txt": "1\n"})
    c2 = a.commit("feat: c2", {"c2.txt": "2\n"})

    _advance_remote(mkrepo, bare, "feat: remote moved", {"remote.txt": "9\n"})

    # The guard: before fetching, the stale force-with-lease REJECTS the push.
    a.bookmark_set("main", c2)
    stale = a.jj("git", "push", "--remote", "origin", "-b", "main", check=False)
    assert stale.returncode != 0
    assert "stale" in stale.stderr.lower() or "unexpectedly moved" in stale.stderr.lower()

    # Reset main so the fetch reconciles cleanly (undo the stale attempt).
    a.jj("bookmark", "set", "main", "-r", base, "--allow-backwards")

    # After fetching, a bare push no longer fails — it would clobber sideways.
    a.fetch("origin")
    a.bookmark_set("main", c2)
    hazard = a.jj("git", "push", "--remote", "origin", "-b", "main", "--dry-run")
    assert "sideways" in hazard.stderr.lower()  # discards the incoming commit

    a.jj("rebase", "-b", "@", "-d", "main@origin")
    assert a.ids(f"main@origin:: & ({c1} | {c2})") == {c1, c2}  # both replayed above incoming
    a.bookmark_set("main", c2)
    safe = a.jj("git", "push", "--remote", "origin", "-b", "main", "--dry-run")
    assert "sideways" not in safe.stderr.lower()  # now a fast-forward, no clobber
    a.push("origin", "main")
    assert a.ids("main@origin") == {c2}


def test_behind_tip_only_rebase_r(mkrepo):
    """Move only the tip onto the incoming tip (Approach B, ``-r``).

    ``jj rebase -r <tip> -d main@origin`` moves only that commit; jj reparents its
    descendants onto its former parent, so the lower commit stays on the old base.
    """
    a, bare, base = _origin_with_main(mkrepo)
    c1 = a.commit("feat: c1", {"c1.txt": "1\n"})
    c2 = a.commit("feat: c2", {"c2.txt": "2\n"})

    _advance_remote(mkrepo, bare, "feat: remote moved", {"remote.txt": "9\n"})
    a.fetch("origin")

    a.jj("rebase", "-r", c2, "-d", "main@origin")
    assert a.ids(f"main@origin:: & {c2}") == {c2}   # c2 moved above the incoming tip
    assert a.ids(f"main@origin:: & {c1}") == set()  # c1 did NOT move (still on old base)


def test_insert_incoming_refused_for_trunk_or_untracked(mkrepo):
    """Approach A is refused when the target is immutable — two ways it can be.

    Landing the incoming commit *under* your work with
    ``jj rebase -r <x> --insert-before @`` fails when ``<x>`` is immutable:
    (a) the trunk ``main@origin`` — always, even though you track it; and
    (b) an **untracked** remote bookmark — untracked remote bookmarks are
    immutable by default. In both cases you cannot move the fetched commit.
    """
    a, bare, base = _origin_with_main(mkrepo)
    a.commit("feat: c1", {"c1.txt": "1\n"})

    # (a) the trunk main@origin is immutable even though `a` tracks it.
    _advance_remote(mkrepo, bare, "feat: remote moved", {"remote.txt": "9\n"})
    a.fetch("origin")
    refused_trunk = a.jj("rebase", "-r", "main@origin", "--insert-before", "@", check=False)
    assert refused_trunk.returncode != 0
    assert "immutable" in refused_trunk.stderr.lower()

    # (b) an UNTRACKED feature bookmark is immutable too.
    _push_feature(mkrepo, bare, "featx", "feat: incoming", {"fx.txt": "1\n"})
    a.fetch("origin")  # featx@origin arrives untracked
    refused_untracked = a.jj("rebase", "-r", "featx@origin", "--insert-before", "@", check=False)
    assert refused_untracked.returncode != 0
    assert "immutable" in refused_untracked.stderr.lower()


def test_insert_incoming_succeeds_on_tracked_feature(mkrepo):
    """Approach A *works* on a tracked, non-trunk feature branch.

    A second repo publishes a feature branch. You fetch it, ``jj bookmark track
    feat@origin`` (it arrives untracked), then ``jj rebase -r feat@origin
    --insert-before @`` **succeeds** — it lands the incoming commit directly under
    ``@``. Your local ``feat`` then diverges from ``feat@origin``, so you publish
    the new position with ``jj git push -b feat``. This is the track → insert →
    push shape, available only for a mutable (non-trunk) branch.
    """
    a, bare, base = _origin_with_main(mkrepo)
    c1 = a.commit("feat: my work", {"c1.txt": "1\n"})

    _push_feature(mkrepo, bare, "feat", "feat: incoming", {"inc.txt": "1\n"})
    a.fetch("origin")

    a.jj("bookmark", "track", "feat@origin")          # track the non-trunk branch first
    a.jj("rebase", "-r", "feat@origin", "--insert-before", "@")  # Approach A succeeds

    assert a.ids("@-") == a.ids("feat")               # incoming landed directly under @
    assert a.ids("feat-") == {c1}                     # above my work
    # change id is stable across the rebase, so divergence shows in the commit id:
    assert a.commit_id("feat") != a.commit_id("feat@origin")  # local diverged from remote-tracking

    a.jj("git", "push", "--remote", "origin", "-b", "feat")   # publish the new position
    assert a.commit_id("feat@origin") == a.commit_id("feat")


def test_divergent_rebase_resolves(mkrepo):
    """Both sides advanced on different files — Approach B replays cleanly.

    Remote advances two commits; local advances one. ``jj rebase -b @`` replays the
    local commit onto the remote tip with no conflict (disjoint files), then push.
    """
    a, bare, base = _origin_with_main(mkrepo)
    mine = a.commit("feat: mine", {"mine.txt": "1\n"})

    b = mkrepo("b")
    b.register_remote("origin", bare)
    b.fetch("origin")
    b.jj("bookmark", "track", "main@origin")
    b.jj("new", "main")
    b.commit("feat: r1", {"r1.txt": "1\n"})
    r2 = b.commit("feat: r2", {"r2.txt": "2\n"})
    b.bookmark_set("main", r2)
    b.push("origin", "main")

    a.fetch("origin")
    a.jj("rebase", "-b", "@", "-d", "main@origin")
    assert a.ids(f"main@origin:: & {mine}") == {mine}  # my work replayed above r2
    a.bookmark_set("main", mine)
    a.push("origin", "main")
    assert a.ids("main@origin") == {mine}


def test_push_to_second_fork_remote(mkrepo):
    """Push a branch to a second (fork) remote, not to origin.

    Golden path is the same with ``--remote=<fork>``. The branch lands on the fork
    bare only.
    """
    a = mkrepo("a")
    a.register_remote("origin")
    a.register_remote("fork")
    base = a.commit("feat: base", {"base.txt": "0\n"})
    a.bookmark_set("main", base)
    a.push("origin", "main")

    work = a.commit("feat: fork work", {"fork.txt": "1\n"})
    a.jj("bookmark", "create", "feature", "-r", work)
    a.jj("git", "push", "--remote", "fork", "-b", "feature")

    assert a.ids("feature@fork") == {work}            # lands on the fork
    assert a.ids("present(feature@origin)") == set()  # not on origin
