#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages(ps: [ps.pytest])" -p "(callPackage ./default.nix { })" -p zellij
"""
test_zellij_llm.py

Self-test for packages/llm/zellij-llm. It runs the built binary (from PATH, via the nix-shell
shebang above, which builds zellij-llm fresh from this directory) against a disposable,
clearly-named scratch zellij session. It does not test the packaged derivation's internals.
Run it directly (./test_zellij_llm.py) or via `pytest test_zellij_llm.py`. Either way nix-shell
builds zellij-llm first and puts it on PATH. It also adds a bare `zellij` for this file's own
session cleanup — zellij-llm's package puts zellij only on *its* PATH, not ours.

It uses a private ZELLIJ_SOCKET_DIR (a short path, see zellij-llm.sh's comment on the macOS
103-byte unix socket limit). A fixture teardown always kills and deletes the scratch session,
even on failure.
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
    # The path must be short — macOS caps a unix socket path at 103 bytes. In a real terminal
    # session (not this sandboxed one, where $TMPDIR is unset) $TMPDIR points at macOS's long
    # per-user /var/folders/.../T path. tempfile.gettempdir() would use it by default. That
    # overflows the socket cap once zellij appends its own
    # /zellij-<uid>/<version>/<session-name> suffix (verified: reproduces the exact "IPC socket
    # path is too long" failure that zellij-llm.sh's ZELLIJ_SOCKET_DIR default avoids). So
    # dir="/tmp" pins TemporaryDirectory to a short parent. This fixture is session-scoped, not
    # per-test, because every test here shares one zellij server behind this socket dir. It
    # tears down once, after the whole run.
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
    # The second spawn must not fail even though the session already exists.
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
    # Regression test: `subscribe --format raw --scrollback` redraws the WHOLE viewport on
    # every update event instead of the delta. Confirmed live: a 3-line command emitted
    # "line-1", "line-1\nline-2", "line-1\nline-2\nline-3" as three separate events. The fix
    # diffs `--format json`'s viewport array instead of a forward of raw output. This test
    # locks that fix in.
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
