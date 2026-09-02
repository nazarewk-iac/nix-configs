"""Advanced / agent-centric analysis idioms over the reference fork topology.

These are the read-only revset/template idioms an agent uses to reason about the
graph before it changes anything. Each asserts a known result on
``build_reference``. See ``test_advanced.md`` for the prose.

They need the rendered fork aliases (``JJ_FORK_CONFIG_TOML``); without it
``harness.slot_config()`` skips them.
"""

from __future__ import annotations

import pytest

import topologies


def _labels(labels, *names):
    return {labels[name] for name in names}


@pytest.fixture
def reference(mkrepo, harness):
    slot_cfg = harness.slot_config()
    repo = mkrepo()
    labels = topologies.build_reference(repo, slot_cfg, push_main_fork=True)
    return repo, labels


def test_reachability_membership_as_a_verdict(reference):
    # Intersect a change with `::<target>` and read emptiness as the answer.
    repo, L = reference
    assert repo.ids(f'{L["A"]} & ::main@fork') == _labels(L, "A")   # published on the fork
    assert repo.ids(f'{L["U2"]} & ::@') == _labels(L, "U2")         # integrated (ancestor of @)
    assert repo.ids(f'{L["P2"]} & ::@') == set()                    # not integrated → diverged/incoming


def test_reusable_vs_frozen_merge_check(reference):
    repo, L = reference
    # non-empty ⇒ the merge is published/immutable, so build a new merge:
    assert repo.ids("tree-merge & (immutable() | pushed)") == _labels(L, "M")


def test_roots_of_a_subgraph(reference):
    repo, L = reference
    assert repo.ids("roots(to-rebase)") == _labels(L, "L1")          # base of the local work
    assert repo.ids("roots(upstream-local)") == _labels(L, "U1")     # base of the local upstream chain


def test_scoping_sets(reference):
    repo, L = reference
    # mutable() = the local work above the frozen merge (rewritable); the pushed
    # history is immutable and excluded.
    assert repo.ids("mutable() & ~root()") == _labels(L, "L1", "L2", "L3", "@")
    # mine() = every harness-authored commit (all of them here).
    assert repo.ids("mine() & ~root()") == set(L.values())
    assert repo.ids("conflicts()") == set()                          # clean tree


def test_files_history(reference):
    repo, L = reference
    # which changes touched a path:
    assert repo.ids('::@ & files("modules/shared.nix")') == _labels(L, "U1", "U2")


def test_parent_introspection_template(reference):
    repo, L = reference
    parents = repo.jj_out(
        "log", "--no-graph", "-r", "tree-merge",
        "-T", 'parents.map(|p| p.change_id().shortest(12)).join(",")',
    )
    # the merge has exactly the upstream tip and the fork commit as parents:
    assert set(parents.split(",")) == {L["U2"], L["F1"]}


def test_identity_probe(reference):
    repo, L = reference
    # `X ~ Y` empty ⟺ X is contained in Y; two single revs are identical when
    # both differences are empty.
    assert repo.ids(f'{L["U2"]} ~ {L["U2"]}') == set()               # same commit
    assert repo.ids(f'{L["U2"]} ~ {L["U1"]}') == _labels(L, "U2")    # different
    # `latest(A..B) ~ B` empty ⇒ B is the newest commit in the range (nothing above it):
    assert repo.ids(f'latest({L["A"]}..{L["U2"]}) ~ {L["U2"]}') == set()


def test_description_filtered_ancestry(reference):
    # Select ancestors of @ whose description matches a keyword, skip empties.
    repo, L = reference
    # both "generic" commits, and no other (`substring:` = a substring match):
    assert repo.ids('::@ & description(substring:"generic") & ~empty()') == _labels(L, "L1", "L3")
    # `~empty()` drops the empty working copy that a broad match would include:
    assert L["@"] in repo.ids('::@ & description(substring:"")')
    assert L["@"] not in repo.ids('::@ & description(substring:"") & ~empty()')


def test_op_log_forensics_and_restore(reference):
    # The op log records every mutation; op restore rewinds to any operation.
    repo, L = reference
    # capture the current operation id (a time-relative template proves the idiom):
    before = repo.jj_out(
        "op", "log", "--no-graph", "-n", "1",
        "-T", 'id.short() ++ " " ++ time.end().ago()',
    ).split()[0]

    # a destructive change: abandon the leaf work
    repo.jj("abandon", L["L3"])
    # `present()` yields empty for an unresolvable id (a bare id would error):
    assert repo.ids(f'present({L["L3"]})') == set()  # gone from the visible graph

    # forensics: the pre-abandon operation is still recorded
    ops = repo.jj_out("op", "log", "--no-graph", "-T", 'id.short() ++ "\n"')
    assert before in ops.split()

    # restore rewinds the repo to the pre-abandon operation:
    repo.jj("op", "restore", before)
    assert repo.ids(L["L3"]) == _labels(L, "L3")     # recovered


def test_file_show_as_a_cross_revision_diff_engine(reference):
    # Read a file at any revision without a checkout — the safe substitute for
    # `jj edit` + read.
    repo, L = reference
    at_u1 = repo.jj_out("file", "show", "-r", L["U1"], "modules/shared.nix")
    at_u2 = repo.jj_out("file", "show", "-r", L["U2"], "modules/shared.nix")
    assert at_u1 == "# u1"
    assert at_u2 == "# u2"
    assert at_u1 != at_u2
