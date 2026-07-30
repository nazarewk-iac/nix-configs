#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages(ps: [ps.pytest])" -p "(callPackage ./default.nix { })" -p zellij
"""
test_zellij_llm.py

Self-test for packages/llm/zellij-llm — exercises the actual built binary (from PATH, via the
nix-shell shebang above, which builds zellij-llm fresh from this directory) against a
disposable, clearly-named scratch zellij session, not the packaged derivation's internals.
Run directly (./test_zellij_llm.py) or via `pytest test_zellij_llm.py`; either way nix-shell
builds zellij-llm first and puts it on PATH (plus a bare `zellij` for this file's own
session-cleanup calls — zellij-llm's own package only puts zellij on *its* PATH, not ours).

Uses a private ZELLIJ_SOCKET_DIR (short path, see zellij-llm.sh's own comment on the macOS
103-byte unix socket limit) and always kills+deletes the scratch session in a fixture
teardown, even on failure.
"""

import json
import os
import subprocess
import tempfile
import time
import uuid

import pytest

SESSION_PREFIX = "llm:nix-configs:selftest-"


@pytest.fixture(scope="session", autouse=True)
def zellij_socket_dir():
    # Must be a short path — macOS caps unix socket paths at 103 bytes. In a real terminal
    # session (not this sandboxed one, where $TMPDIR happens to be unset) $TMPDIR is set to
    # macOS's long per-user /var/folders/.../T path, which tempfile.gettempdir() would use by
    # default and which overflows the socket cap once zellij's own
    # /zellij-<uid>/<version>/<session-name> suffix is appended (verified: reproduces the
    # exact "IPC socket path is too long" failure zellij-llm.sh's own ZELLIJ_SOCKET_DIR
    # default exists to avoid) — dir="/tmp" pins TemporaryDirectory to a short parent instead.
    # Session-scoped (not per-test) since every test in this file shares one zellij server
    # instance behind this socket dir; only torn down once, after the whole run.
    with tempfile.TemporaryDirectory(dir="/tmp", prefix="kdn-test-zellij-") as socket_dir:
        os.environ["ZELLIJ_SOCKET_DIR"] = socket_dir
        yield socket_dir


@pytest.fixture()
def session():
    name = f"{SESSION_PREFIX}{uuid.uuid4().hex[:8]}"
    try:
        yield name
    finally:
        subprocess.run(["zellij", "kill-session", name], capture_output=True)
        subprocess.run(["zellij", "delete-session", name], capture_output=True)


def run(*args, input_text=None, check=True):
    return subprocess.run(
        args,
        input=input_text,
        capture_output=True,
        text=True,
        check=check,
    )


def list_panes(sess):
    out = run("zellij-llm", "list", "--session", sess)
    return json.loads(out.stdout)


def wait_for(predicate, timeout=10, interval=0.2):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


def test_spawn_creates_session_and_runs_stdin_script(session):
    run("zellij-llm", "spawn", "--session", session, "--pane", "p1", input_text="echo hi-from-p1\n")
    assert wait_for(lambda: any(p["title"] == "p1" and p["exited"] for p in list_panes(session)))
    panes = {p["title"]: p for p in list_panes(session)}
    assert panes["p1"]["exit_status"] == 0


def test_spawn_is_idempotent_on_existing_session(session):
    run("zellij-llm", "spawn", "--session", session, "--pane", "p1", input_text="true\n")
    # second spawn must not fail even though the session already exists
    run("zellij-llm", "spawn", "--session", session, "--pane", "p2", input_text="true\n")
    assert wait_for(lambda: len(list_panes(session)) >= 3)  # default pane + p1 + p2


def test_peek_returns_pane_output_by_title_and_by_id(session):
    run("zellij-llm", "spawn", "--session", session, "--pane", "p1", input_text="echo peekable\n")
    wait_for(lambda: any(p["title"] == "p1" and p["exited"] for p in list_panes(session)))

    by_title = run("zellij-llm", "peek", "--session", session, "--pane", "p1")
    assert "peekable" in by_title.stdout

    pane_id = next(p["id"] for p in list_panes(session) if p["title"] == "p1")
    by_id = run("zellij-llm", "peek", "--session", session, "--pane", str(pane_id))
    assert "peekable" in by_id.stdout


def test_spawn_and_watch_heartbeat_reports_exit_code(session):
    out = run(
        "zellij-llm", "spawn-and-watch",
        "--session", session, "--pane", "watch-hb",
        "--mode", "heartbeat", "--interval", "1",
        input_text="sleep 2\nexit 7\n",
        check=False,
    )
    assert out.returncode == 7
    assert "EXIT:7" in out.stdout


def test_spawn_and_watch_stream_reports_exit_code(session):
    out = run(
        "zellij-llm", "spawn-and-watch",
        "--session", session, "--pane", "watch-stream",
        "--mode", "stream",
        input_text="echo streamed-line\nexit 3\n",
        check=False,
    )
    assert out.returncode == 3
    assert "EXIT:3" in out.stdout


def test_spawn_and_watch_stream_does_not_duplicate_lines(session):
    # Regression test: `subscribe --format raw --scrollback` redraws the ENTIRE viewport on
    # every update event rather than emitting just the delta — confirmed live, a 3-line
    # command produced "line-1", "line-1\nline-2", "line-1\nline-2\nline-3" as three separate
    # emissions. Fixed by diffing `--format json`'s viewport array instead of forwarding raw
    # output; this locks that fix in.
    out = run(
        "zellij-llm", "spawn-and-watch",
        "--session", session, "--pane", "watch-stream-dup",
        "--mode", "stream",
        input_text="echo alpha\necho bravo\necho charlie\nexit 0\n",
        check=False,
    )
    assert out.returncode == 0
    lines = out.stdout.splitlines()
    assert lines.count("alpha") == 1
    assert lines.count("bravo") == 1
    assert lines.count("charlie") == 1


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
