#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages(ps: [ps.pytest])" -p "(callPackage ./default.nix { })" -p jujutsu -p git
"""
test_kdn_slug.py

Self-test for packages/llm/kdn-slug — exercises the actual built binary (from PATH, via the
nix-shell shebang above, which builds kdn-slug fresh from this directory) rather than the
packaged derivation's internals. Run directly (./test_kdn_slug.py) or via `pytest
test_kdn_slug.py`; either way nix-shell builds kdn-slug first and puts it on PATH.

`repo`/auto-discovery tests run against a disposable jj-colocated repo stub with a fake
GitHub remote (see `jj_repo` fixture below), recreated fresh per test via pytest's
function-scoped `tmp_path` — matching this actual repo's own topology (jj colocated with
git), which is what kdn-slug's `repo` subcommand checks first (`jj root`/`jj git remote
list`, falling back to plain git only when not in a jj repo at all).
"""

import subprocess

import pytest


def run(*args, cwd=None, check=True):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=check)


@pytest.fixture()
def jj_repo(tmp_path):
    # tmp_path resolves through /private on macOS — jj root/git rev-parse report the
    # resolved path, so tests must compare against the resolved path too, not tmp_path as-is.
    repo_dir = (tmp_path / "acme-widgets").resolve()
    repo_dir.mkdir()
    run("jj", "git", "init", "--colocate", cwd=repo_dir)
    run("jj", "git", "remote", "add", "origin", "git@github.com:some-org/acme-widgets.git", cwd=repo_dir)
    return repo_dir


@pytest.fixture()
def plain_git_repo(tmp_path):
    # No jj at all (unlike jj_repo above) — exercises kdn-slug's non-jj fallback path
    # specifically. No remote either, so `repo` must fall back to just the directory name.
    repo_dir = (tmp_path / "just-a-dir").resolve()
    repo_dir.mkdir()
    run("git", "init", "-q", cwd=repo_dir)
    return repo_dir


def test_names_session_uses_overrides_and_llm_prefix():
    out = run("kdn-slug", "names", "--type", "session", "--repo", "myrepo", "--session-id", "deadbeef")
    assert out.stdout.strip() == "llm:myrepo:deadbeef"


def test_names_session_appends_tags_in_order():
    out = run(
        "kdn-slug", "names", "--type", "session",
        "--repo", "myrepo", "--session-id", "deadbeef", "--tag", "foo", "--tag", "bar",
    )
    assert out.stdout.strip() == "llm:myrepo:deadbeef:foo:bar"


def test_names_session_respects_max_len_with_hard_truncation_fallback():
    # --repo/--session-id here only ever produce one candidate ("llm:myrepo:deadbeef" — no
    # org/host to drop, and "deadbeef" is exactly 8 chars so no shorter session-id variant
    # exists either), so a --max-len below its length must hit the hard-truncation fallback
    # of that single candidate, not fall back to a shorter *different* candidate.
    out = run(
        "kdn-slug", "names", "--type", "session",
        "--repo", "myrepo", "--session-id", "deadbeef", "--max-len", "6",
    )
    result = out.stdout.strip()
    assert result == "llm:myrepo:deadbeef"[:6]


def test_names_tab_has_no_llm_prefix():
    out = run("kdn-slug", "names", "--type", "tab", "--tag", "agent1", "--tag", "build")
    assert out.stdout.strip() == "agent1:build"


def test_names_custom_separator():
    out = run("kdn-slug", "names", "--type", "tab", "--sep", "-", "--tag", "agent1", "--tag", "build")
    assert out.stdout.strip() == "agent1-build"


def test_names_list_shows_multiple_candidates_most_detailed_first():
    out = run(
        "kdn-slug", "names", "--type", "session", "--list",
        "--repo", "myrepo", "--session-id", "0123456789abcdef",
    )
    lines = out.stdout.strip().splitlines()
    assert len(lines) > 1
    assert lines[0] == "llm:myrepo:0123456789abcdef"
    # every later line must be no longer than the previous (most detailed first)
    assert all(len(a) >= len(b) for a, b in zip(lines, lines[1:]))


def test_repo_detects_jj_colocated_repo_with_github_remote(jj_repo):
    out = run("kdn-slug", "repo", cwd=jj_repo)
    fields = dict(line.split("=", 1) for line in out.stdout.strip().splitlines())
    assert fields["root"] == str(jj_repo)
    assert fields["name"] == "acme-widgets"
    assert fields["org"] == "some-org"
    assert fields["host"] == "github.com"


def test_repo_falls_back_to_dirname_without_a_remote(plain_git_repo):
    out = run("kdn-slug", "repo", cwd=plain_git_repo)
    fields = dict(line.split("=", 1) for line in out.stdout.strip().splitlines())
    assert fields["root"] == str(plain_git_repo)
    assert fields["name"] == "just-a-dir"
    assert fields["org"] == ""
    assert fields["host"] == ""


def test_names_session_auto_discovers_repo_from_jj_repo(jj_repo):
    out = run(
        "kdn-slug", "names", "--type", "session", "--session-id", "deadbeef",
        cwd=jj_repo,
    )
    assert out.stdout.strip() == "llm:github.com/some-org/acme-widgets:deadbeef"


def test_list_types_includes_session_tab_pane():
    out = run("kdn-slug", "list-types")
    assert set(out.stdout.strip().splitlines()) == {"session", "tab", "pane"}


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
