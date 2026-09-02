"""De-leak and cross-dependency (X→Y) golden paths.

Local work above the merge is mutable (the merge below is frozen), so these
recipes rewrite only mutable commits. See ``test_deleak.md`` for the prose.
"""

from __future__ import annotations

import pytest

import topologies


@pytest.fixture
def base(mkrepo, harness):
    slot = harness.slot_config()
    repo = mkrepo()
    labels = topologies.build_base_tree(repo, slot)
    return repo, labels


def test_deleak_by_splitting_content(base):
    """A commit mixing generic + fork-sensitive content is fork-leaked.

    Split the sensitive file out; the generic remainder becomes upstream-safe and
    only the isolated sensitive commit stays fork-directed.
    """
    repo, L = base
    repo.write("modules/generic.nix", "# generic\n")
    repo.write("hosts/PLACEHOLDER-SENSITIVE-mix.nix", "# sensitive\n")
    repo.describe("feat: mixed work")
    mixed = repo.change_id("@")
    assert repo.ids("fork-leaked") == {mixed}   # the mixed commit is leaked

    # Split the sensitive file into its own commit; the generic remainder stays
    # in @ (jj keeps the selected files in the parent, the rest in @).
    repo.jj("split", "-m", "feat(fork): sensitive part", "--", "hosts/PLACEHOLDER-SENSITIVE-mix.nix")
    generic = repo.change_id("@")     # remainder — generic only
    sensitive = repo.change_id("@-")  # the split-out sensitive commit

    assert repo.ids("fork-leaked") == {sensitive}   # only the sensitive commit stays leaked
    assert generic in repo.ids("upstream-safe")       # the generic part is now clean
    assert generic not in repo.ids("fork-leaked")


def test_deleak_by_rewording(base):
    """A generic commit is fork-leaked only because its message carries the term.

    Reword it to a neutral message; ``fork-leaked`` empties.
    """
    repo, L = base
    repo.write("modules/generic.nix", "# generic\n")
    repo.describe("feat: PLACEHOLDER-SENSITIVE thing")
    c = repo.change_id("@")
    assert repo.ids("fork-leaked") == {c}

    repo.describe("feat: neutral thing")
    assert repo.ids("fork-leaked") == set()


def test_make_x_an_ancestor_of_y(base):
    """Fork change Y depends on generic change X; make X an ancestor of Y.

    ``jj rebase -s Y -d X -d <Y-old-parent>`` makes Y a merge of X and its old
    parent, so X is now in Y's ancestry, and Y keeps its old parent.
    """
    repo, L = base
    m = L["M"]

    repo.new(m)
    repo.write("modules/slotx.nix", "# slot X\n")
    repo.describe("feat: slot X")
    x = repo.change_id("@")

    repo.new(m)
    repo.write("hosts/PLACEHOLDER-SENSITIVE-y.nix", "# host Y uses slot X\n")
    repo.describe("feat: host Y")
    y = repo.change_id("@")
    assert repo.ids(f"parents({y})") == {m}

    repo.jj("rebase", "-s", y, "-d", x, "-d", m)

    assert repo.ids(f"parents({y})") == {x, m}     # Y is now a merge of X and its old parent
    assert repo.ids(f"{x} & ::{y}") == {x}          # X is an ancestor of Y
