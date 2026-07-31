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

It sets a private ZELLIJ_SOCKET_DIR (a short path, see zellij-llm.sh's comment on the macOS
103-byte unix socket limit). ZELLIJ_SOCKET_DIR is a test-only device. zellij-llm never sets a
default for it at runtime; the tool relies on a short derived session name to fit the socket
path. A fixture teardown always kills and deletes each scratch session, even on failure.
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
    # /zellij-<uid>/<version>/<session-name> suffix. So dir="/tmp" pins TemporaryDirectory to a
    # short parent. The tests pass an explicit --session, so the socket path stays short. This
    # fixture is session-scoped, not per-test, because every test here shares one zellij server
    # behind this socket dir. It tears down once, after the whole run.
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


def test_spawn_persists_pane_by_default(session):
    # Default behavior keeps the pane after the command exits, so the user can attach and review.
    run("zellij-llm", "spawn", "--session", session, "--pane", "keep", input_text="true\n")
    assert wait_for(lambda: any(p["title"] == "keep" and p["exited"] for p in list_panes(session)))
    # The pane is still present after it exited.
    assert any(p["title"] == "keep" for p in list_panes(session))


def test_spawn_ephemeral_closes_pane_on_exit(session):
    # --ephemeral closes the pane the moment its command exits, so it disappears from the list.
    run("zellij-llm", "spawn", "--session", session, "--pane", "eph", "--ephemeral", input_text="true\n")
    assert wait_for(lambda: all(p["title"] != "eph" for p in list_panes(session)))


def test_spawn_wait_stream_matches_spawn_and_watch(session):
    # `spawn --wait --mode stream` is the same behavior as `spawn-and-watch --mode stream`.
    out = run(
        "zellij-llm", "spawn",
        "--session", session, "--pane", "sw",
        "--wait", "--mode", "stream",
        input_text="echo waited-line\nexit 4\n",
        check=False,
    )
    assert out.returncode == 4
    assert "waited-line" in out.stdout
    assert "EXIT:4" in out.stdout


def test_watch_follows_existing_pane_to_exit(session):
    # Spawn without waiting, then attach with `watch` and follow the pane until it exits.
    run("zellij-llm", "spawn", "--session", session, "--pane", "later", input_text="sleep 1\nexit 6\n")
    out = run(
        "zellij-llm", "watch",
        "--session", session, "--pane", "later", "--mode", "stream",
        check=False,
    )
    assert out.returncode == 6
    assert "EXIT:6" in out.stdout


def test_wait_blocks_until_exit_and_returns_code(session):
    # `wait` blocks until the pane's command exits, then reports EXIT:<code> with no streaming.
    run("zellij-llm", "spawn", "--session", session, "--pane", "wp", input_text="sleep 1\nexit 2\n")
    out = run("zellij-llm", "wait", "--session", session, "--pane", "wp", "--interval", "1", check=False)
    assert out.returncode == 2
    assert "EXIT:2" in out.stdout
    # No pane output leaks into a wait; it reports only the exit line.
    assert out.stdout.strip() == "EXIT:2"


def test_spawn_rejects_oversized_session_name(session):
    # A session name that overflows the socket-path limit must fail early with a clear message,
    # not deep inside zellij. Use an explicit oversized --session to trigger the check.
    long_name = "x" * 120
    out = run("zellij-llm", "spawn", "--session", long_name, "--pane", "p", input_text="true\n", check=False)
    assert out.returncode != 0
    assert "socket path is too long" in out.stderr


def test_derived_session_fits_socket_and_runs(session):
    # With no --session, the name is derived from kdn-slug and capped to the socket budget. A
    # long harness session id must still produce a working, short-enough session. `session` is
    # unused here except to guarantee teardown of any stray derived session with our prefix does
    # not clash; the derived name uses kdn-slug's own scheme.
    env = dict(os.environ)
    env["CLAUDE_CODE_SESSION_ID"] = "deadbeef-1111-2222-3333-444455556666"
    proc = subprocess.run(
        ["zellij-llm", "spawn", "--pane", "derived", "--max-len", "24"],
        input="echo derived-ok\n",
        capture_output=True,
        text=True,
        env=env,
    )
    assert proc.returncode == 0, proc.stderr
    # The tool reports the short derived session name it chose.
    assert "spawned pane 'derived'" in proc.stdout
    derived = proc.stdout.split("session '", 1)[1].rstrip("'\n")
    try:
        assert len(derived) <= 24
    finally:
        subprocess.run(["zellij", "kill-session", derived], capture_output=True, env=env)
        subprocess.run(["zellij", "delete-session", derived], capture_output=True, env=env)


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
