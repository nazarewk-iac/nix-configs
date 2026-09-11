"""Pre-push hook cases: which remote may receive private content.

The hook is `hack/pre-push.sh`. The suite reads its path from
`KDN_JJ_PRE_PUSH_SH` and runs the plain script, so each case bakes its own
pattern lists. Every pattern here is a PLACEHOLDER-* string; no real sensitive
term appears. See test_prepush.md for the prose.
"""

from __future__ import annotations

import os
import subprocess

import pytest

ZERO_SHA = "0" * 40
FORK_REMOTE = "fork"
PUBLIC_REMOTE = "upstream"

FILE_PATTERNS = ["PLACEHOLDER-SENSITIVE", "PLACEHOLDER-PREFIX-"]
MESSAGE_PATTERNS = ["PLACEHOLDER-SENSITIVE"]
BLOCKED_PATTERNS = ["PLACEHOLDER-BLOCKED"]

# A path that matches a file pattern, and a path that matches none.
PRIVATE_PATH = "hosts/PLACEHOLDER-PREFIX-1/default.nix"
PUBLIC_PATH = "docs/note.md"


def hook_script() -> str:
    path = os.environ.get("KDN_JJ_PRE_PUSH_SH")
    if not path:
        pytest.skip("KDN_JJ_PRE_PUSH_SH is not set (run in the devenv or the check)")
    return path


def run_hook(
    repo,
    remote,
    refs: str = "",
    *,
    file_patterns=FILE_PATTERNS,
    message_patterns=MESSAGE_PATTERNS,
    blocked_patterns=BLOCKED_PATTERNS,
    extra_env: dict | None = None,
):
    """Run the hook for one remote. ``refs`` is the stdin git normally writes.

    ``remote=None`` omits argv[1], which is the pre-commit-framework shape.
    """
    env = dict(repo.env)
    # The hook falls back to these when argv holds no remote. Clear them so a
    # case that omits the remote really sees an unknown remote.
    for key in ("PRE_COMMIT_REMOTE_NAME", "PRE_COMMIT_REMOTE_URL", "PRE_COMMIT_REMOTE_BRANCH"):
        env.pop(key, None)
    env["PRIVATE_REMOTE"] = FORK_REMOTE
    env["SENSITIVE_FILE_PATTERNS"] = "\n".join(file_patterns)
    env["SENSITIVE_MESSAGE_PATTERNS"] = "\n".join(message_patterns)
    env["BLOCK_PUSH_MESSAGE_PATTERNS"] = "\n".join(blocked_patterns)
    env.update(extra_env or {})

    argv = ["bash", hook_script()]
    if remote is not None:
        argv.append(remote)
    return subprocess.run(
        argv,
        cwd=repo.path,
        env=env,
        input=refs,
        capture_output=True,
        text=True,
    )


def build_base(mkrepo):
    """One commit on `main`, pushed to the public and to the private remote.

    Both pushes go through ``push_to`` (raw ``git push`` plus ``jj git import``),
    not through ``jj git push``. Measured on jj 0.45.1: ``jj git push`` creates a
    new remote bookmark on the FIRST remote only. A second remote then fails with
    ``Refusing to create new remote bookmark main@<remote>``, and its hint names a
    ref that does not exist yet. A raw push writes the remote-tracking ref
    ``refs/remotes/<remote>/main`` as well, which the hook's ``--remotes=<remote>``
    range needs.
    """
    repo = mkrepo()
    base = repo.commit("feat: base", {"README.md": "base\n"})
    repo.register_remote(PUBLIC_REMOTE)
    repo.register_remote(FORK_REMOTE)
    repo.bookmark_set("main", base)
    repo.push_to(PUBLIC_REMOTE, "main", "main")
    repo.push_to(FORK_REMOTE, "main", "main")
    return repo, repo.commit_id(base)


def add_tip(repo, message: str, files: dict) -> str:
    """Add one commit, move `main` onto it, and return its git commit id."""
    cid = repo.commit(message, files)
    repo.bookmark_set("main", cid)
    return repo.commit_id(cid)


def refline(local_sha: str, remote_sha: str) -> str:
    return f"refs/heads/main {local_sha} refs/heads/main {remote_sha}\n"


# --- the direction of the guard ---------------------------------------------


def test_public_remote_blocks_a_sensitive_path(mkrepo):
    """The point of the hook: private content must not reach a public remote."""
    repo, base = build_base(mkrepo)
    tip = add_tip(repo, "feat: add a host", {PRIVATE_PATH: "{ }\n"})

    result = run_hook(repo, PUBLIC_REMOTE, refline(tip, base))

    assert result.returncode == 1
    assert "a path matches a sensitive pattern" in result.stderr
    # The hook never prints the pattern itself, only the matching path.
    assert PRIVATE_PATH in result.stderr


def test_private_remote_permits_a_sensitive_path(mkrepo):
    """The fork remote is where the private content belongs."""
    repo, base = build_base(mkrepo)
    tip = add_tip(repo, "feat: add a host", {PRIVATE_PATH: "{ }\n"})

    result = run_hook(repo, FORK_REMOTE, refline(tip, base))

    assert result.returncode == 0, result.stderr


def test_public_remote_blocks_a_sensitive_message(mkrepo):
    repo, base = build_base(mkrepo)
    tip = add_tip(repo, "chore: touch PLACEHOLDER-SENSITIVE", {PUBLIC_PATH: "text\n"})

    public = run_hook(repo, PUBLIC_REMOTE, refline(tip, base))
    private = run_hook(repo, FORK_REMOTE, refline(tip, base))

    assert public.returncode == 1
    assert "a commit message matches a sensitive pattern" in public.stderr
    assert private.returncode == 0, private.stderr


def test_public_remote_blocks_a_sensitive_line_in_a_public_path(mkrepo):
    """A path check is not enough: a public name can hold a private string."""
    repo, base = build_base(mkrepo)
    tip = add_tip(repo, "docs: add a note", {PUBLIC_PATH: "see PLACEHOLDER-SENSITIVE\n"})

    public = run_hook(repo, PUBLIC_REMOTE, refline(tip, base))
    private = run_hook(repo, FORK_REMOTE, refline(tip, base))

    assert public.returncode == 1
    assert "a diff line matches a sensitive pattern" in public.stderr
    assert private.returncode == 0, private.stderr


def test_always_blocked_message_stops_both_remotes(mkrepo):
    """This check runs before the private-remote exit, so it covers every remote."""
    repo, base = build_base(mkrepo)
    tip = add_tip(repo, "wip: PLACEHOLDER-BLOCKED", {PUBLIC_PATH: "text\n"})

    for remote in (PUBLIC_REMOTE, FORK_REMOTE):
        result = run_hook(repo, remote, refline(tip, base))
        assert result.returncode == 1, remote
        assert "matches an always-blocked pattern" in result.stderr


def test_a_clean_commit_passes_on_both_remotes(mkrepo):
    repo, base = build_base(mkrepo)
    tip = add_tip(repo, "docs: add a note", {PUBLIC_PATH: "text\n"})

    for remote in (PUBLIC_REMOTE, FORK_REMOTE):
        result = run_hook(repo, remote, refline(tip, base))
        assert result.returncode == 0, result.stderr


# --- fail-safe behaviour ----------------------------------------------------


def test_an_empty_pattern_list_fails_loudly(mkrepo):
    """The lists come from a git-ignored file, so an empty list is a defect.

    A silent pass here would disable the guard with no warning.
    """
    repo, base = build_base(mkrepo)
    tip = add_tip(repo, "feat: add a host", {PRIVATE_PATH: "{ }\n"})

    result = run_hook(
        repo,
        PUBLIC_REMOTE,
        refline(tip, base),
        file_patterns=[],
        message_patterns=[],
    )

    assert result.returncode == 1
    assert "cannot protect anything" in result.stderr


def test_an_empty_pattern_list_has_an_explicit_escape_hatch(mkrepo):
    repo, base = build_base(mkrepo)
    tip = add_tip(repo, "docs: add a note", {PUBLIC_PATH: "text\n"})

    result = run_hook(
        repo,
        PUBLIC_REMOTE,
        refline(tip, base),
        file_patterns=[],
        message_patterns=[],
        extra_env={"KDN_JJ_PRE_PUSH_ALLOW_EMPTY": "1"},
    )

    assert result.returncode == 0, result.stderr
    assert "cannot protect anything" in result.stderr


def test_an_unknown_remote_is_treated_as_public(mkrepo):
    """No argv and no PRE_COMMIT_* variable must not permit private content."""
    repo, base = build_base(mkrepo)
    tip = add_tip(repo, "feat: add a host", {PRIVATE_PATH: "{ }\n"})

    result = run_hook(repo, None, refline(tip, base))

    assert result.returncode == 1
    assert "a path matches a sensitive pattern" in result.stderr


def test_no_ref_lines_fails_closed_for_a_public_remote(mkrepo):
    """prek hands a pre-push hook no stdin, so the hook cannot tell what moves."""
    repo, _base = build_base(mkrepo)
    add_tip(repo, "feat: add a host", {PRIVATE_PATH: "{ }\n"})

    result = run_hook(repo, PUBLIC_REMOTE, "")

    assert result.returncode == 1
    assert "no ref lines on stdin" in result.stderr


def test_no_ref_lines_passes_for_the_private_remote(mkrepo):
    repo, _base = build_base(mkrepo)
    add_tip(repo, "feat: add a host", {PRIVATE_PATH: "{ }\n"})

    result = run_hook(repo, FORK_REMOTE, "")

    assert result.returncode == 0, result.stderr
    assert "WARNING" in result.stderr


def test_a_named_range_replaces_the_missing_stdin(mkrepo):
    """KDN_JJ_PRE_PUSH_RANGE is the documented way past the no-stdin failure."""
    repo, base = build_base(mkrepo)
    tip = add_tip(repo, "feat: add a host", {PRIVATE_PATH: "{ }\n"})

    result = run_hook(
        repo,
        PUBLIC_REMOTE,
        "",
        extra_env={"KDN_JJ_PRE_PUSH_RANGE": f"{base}..{tip}"},
    )

    assert result.returncode == 1
    assert "a path matches a sensitive pattern" in result.stderr


# --- ref-line shapes --------------------------------------------------------


def test_a_new_ref_checks_the_commits_the_remote_lacks(mkrepo):
    """A new ref carries a zero remote sha, so there is no range to diff.

    A `git diff <zero-sha> <sha>` call fails on that input, so the hook asks git
    for the commits the target remote does not hold yet instead.
    """
    repo, _base = build_base(mkrepo)
    tip = add_tip(repo, "feat: add a host", {PRIVATE_PATH: "{ }\n"})

    result = run_hook(repo, PUBLIC_REMOTE, refline(tip, ZERO_SHA))

    assert result.returncode == 1
    assert "a path matches a sensitive pattern" in result.stderr
    # A zero sha must never reach git as a revision.
    assert ZERO_SHA not in result.stderr


def test_a_new_ref_of_a_clean_commit_passes(mkrepo):
    repo, _base = build_base(mkrepo)
    tip = add_tip(repo, "docs: add a note", {PUBLIC_PATH: "text\n"})

    result = run_hook(repo, PUBLIC_REMOTE, refline(tip, ZERO_SHA))

    assert result.returncode == 0, result.stderr


def test_a_delete_only_push_falls_back_to_the_no_stdin_path(mkrepo):
    """A zero local sha is a delete, so the hook skips it — and then sees no ref.

    So a delete-only push to a public remote fails closed. That is safe, but it
    is a false positive. test_prepush.md records it as a known limit.
    """
    repo, base = build_base(mkrepo)

    result = run_hook(repo, PUBLIC_REMOTE, refline(ZERO_SHA, base))

    assert result.returncode == 1
    assert "no ref lines on stdin" in result.stderr
