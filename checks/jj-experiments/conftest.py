"""Isolated jj test harness for fork and branch use-case experiments.

Every test runs jj and git fully isolated from the developer's ``$HOME``. The
fixtures point ``HOME``, the ``XDG_*`` dirs, ``JJ_CONFIG``, and the git global
and system config into a per-test temp tree. Nothing reads or writes the real
user config. jj keeps its own state in each repo's ``.jj/`` dir, so every write
stays inside the temp tree.

Use the ``mkrepo`` fixture to make disposable colocated jj repos and bare
remotes. Build a known graph with the ``Repo`` helpers, then assert the result
with ``Repo.ids`` or read it with ``Repo.log_graph``. The paired ``<group>.md``
files explain the use-cases that each test group shows.

Design notes:

- Commit timestamps are deterministic. jj ``latest()`` (and the ``*-tip``
  aliases built on it) pick by commit time, so each commit gets an explicit,
  increasing time through ``--config debug.commit-timestamp``.
- The fork revset aliases come from the real slot. The check derivation and the
  ``devenv shell`` both export ``JJ_FORK_CONFIG_TOML`` with the rendered config.
  A test that needs the aliases calls ``harness.slot_config()``; it skips when
  the env var is absent (for example a bare ``pytest`` run with no slot).
"""

from __future__ import annotations

import dataclasses
import datetime as _dt
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

# Arbitrary fixed base time (2023-11-14T22:13:20Z). Each commit adds a step, so
# commit order is stable and `latest()` is deterministic without sleeps.
_EPOCH = 1_700_000_000
_STEP = 60


def _iso(ts: int) -> str:
    return _dt.datetime.fromtimestamp(ts, tz=_dt.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%S+00:00"
    )


_BARE_KEY = re.compile(r"[A-Za-z0-9_-]+")


def _toml_key(key: str) -> str:
    """Quote a single config key segment when it is not a bare TOML key."""
    if _BARE_KEY.fullmatch(key):
        return key
    return '"' + key.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _toml_value(value) -> str:
    """Render a Python value as a TOML value for ``jj --config NAME=VALUE``."""
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, (list, tuple)):
        return "[" + ", ".join(_toml_value(v) for v in value) + "]"
    raise TypeError(f"unsupported TOML value: {value!r}")


@dataclasses.dataclass
class JJConfig:
    """A layered jj config for one repo.

    The base is the rendered slot TOML (copied into the repo config file).
    Overlays are applied as ``--config`` args on every jj call, so they win over
    the base. Overlays split into active and deferred sets. A deferred overlay
    (for example ``trunk()`` or ``immutable_heads()`` that names a bookmark not
    yet created) applies only after ``activate_deferred``. This avoids the trap
    where an alias that names a missing ref breaks every jj command.
    """

    base_toml: Path | None = None
    base_scope: str = "repo"
    _flag: list[str] = dataclasses.field(default_factory=list)
    _flag_deferred: list[str] = dataclasses.field(default_factory=list)
    # Persistent entries live in a config file layer (user/repo/workspace),
    # applied by ``Repo`` via `jj config set`. Command aliases MUST be here —
    # jj refuses them from the `--config` flag.
    _persistent: list = dataclasses.field(default_factory=list)

    # The four jj config targets. "flag" is the ephemeral `--config` layer
    # (highest precedence, per invocation). The rest are file layers.
    SCOPES = ("flag", "user", "repo", "workspace")

    @classmethod
    def from_slot(cls, path, *, scope: str = "repo") -> "JJConfig":
        return cls(base_toml=Path(path), base_scope=scope)

    @classmethod
    def without_slot(cls) -> "JJConfig":
        return cls(base_toml=None)

    def _put(self, scope: str, dotted: str, value, *, deferred: bool = False) -> "JJConfig":
        if scope not in self.SCOPES:
            raise ValueError(f"unknown scope {scope!r}; use one of {self.SCOPES}")
        if scope == "flag":
            entry = f"{dotted}={_toml_value(value)}"
            (self._flag_deferred if deferred else self._flag).append(entry)
        else:
            if deferred:
                raise ValueError("deferred applies only to the flag scope")
            self._persistent.append((scope, dotted, value))
        return self

    def revset_alias(self, name: str, expr: str, *, scope: str = "flag", deferred: bool = False):
        return self._put(scope, f"revset-aliases.{_toml_key(name)}", expr, deferred=deferred)

    def alias(self, name: str, argv, *, scope: str = "repo"):
        """Record a command alias in a file layer (user/repo/workspace).

        jj refuses command aliases from the `--config` flag, so ``scope="flag"``
        is rejected. Aliases known before ``mkrepo`` apply at repo creation; add
        a later one with ``Repo.define_alias``.
        """
        if scope == "flag":
            raise ValueError("command aliases cannot use the flag scope")
        return self._put(scope, f"aliases.{_toml_key(name)}", list(argv))

    def set(self, dotted: str, value, *, scope: str = "flag", deferred: bool = False):
        # `dotted` must already be a valid TOML key path (the caller controls it).
        return self._put(scope, dotted, value, deferred=deferred)

    def merge(self, mapping: dict, *, prefix: str = "", scope: str = "flag", deferred: bool = False):
        for key, value in mapping.items():
            dotted = f"{prefix}.{_toml_key(key)}" if prefix else _toml_key(key)
            if isinstance(value, dict):
                self.merge(value, prefix=dotted, scope=scope, deferred=deferred)
            else:
                self._put(scope, dotted, value, deferred=deferred)
        return self

    def activate_deferred(self) -> "JJConfig":
        self._flag.extend(self._flag_deferred)
        self._flag_deferred.clear()
        return self

    def config_args(self) -> list[str]:
        args: list[str] = []
        for entry in self._flag:
            args += ["--config", entry]
        return args

    def persistent(self) -> list:
        """Return the (scope, dotted-key, value) entries for the file layers."""
        return list(self._persistent)


@dataclasses.dataclass
class Repo:
    """A disposable colocated jj repo with an isolated env.

    ``path`` is the repo dir. ``jj``/``git`` run a command inside it. ``cfg`` is
    the ``JJConfig`` for this repo. ``register_remote`` adds a bare remote. The
    build helpers create commits with deterministic times.
    """

    path: Path
    env: dict
    cfg: JJConfig
    harness: "Harness"
    _ts: int = _EPOCH

    # --- raw command runners -------------------------------------------------
    def jj(self, *args, check: bool = True, input: str | None = None):
        cmd = ["jj", "--no-pager", *self.cfg.config_args(), *args]
        return subprocess.run(
            cmd,
            cwd=self.path,
            env=self.env,
            capture_output=True,
            text=True,
            check=check,
            input=input,
        )

    def jj_out(self, *args, **kw) -> str:
        return self.jj(*args, **kw).stdout.strip()

    def git(self, *args, check: bool = True):
        return subprocess.run(
            ["git", *args],
            cwd=self.path,
            env=self.env,
            capture_output=True,
            text=True,
            check=check,
        )

    # --- content and history builders ---------------------------------------
    def write(self, relpath: str, content: str = "") -> "Repo":
        target = self.path / relpath
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        return self

    def _next_ts(self, ts: int | None) -> str:
        if ts is None:
            self._ts += _STEP
            ts = self._ts
        else:
            self._ts = max(self._ts, ts)
        return _iso(ts)

    def describe(self, message: str, *, rev: str = "@", ts: int | None = None) -> "Repo":
        self.jj(
            "--config",
            f"debug.commit-timestamp={self._next_ts(ts)}",
            "describe",
            rev,
            "-m",
            message,
        )
        return self

    def new(self, *parents: str, message: str | None = None, ts: int | None = None) -> str:
        """Create a new commit on the given parents and move ``@`` onto it.

        Returns the new change id. Pass a message to describe it at once.
        """
        args = ["--config", f"debug.commit-timestamp={self._next_ts(ts)}", "new", *parents]
        if message is not None:
            args += ["-m", message]
        self.jj(*args)
        return self.change_id("@")

    def commit(self, message: str, files: dict[str, str], *, ts: int | None = None) -> str:
        """Write files into ``@``, describe it, then start a fresh empty ``@``.

        Returns the change id of the just-described (now parent) commit.
        """
        for relpath, content in files.items():
            self.write(relpath, content)
        self.describe(message, ts=ts)
        cid = self.change_id("@")
        self.new()
        return cid

    # --- queries -------------------------------------------------------------
    def change_id(self, rev: str = "@") -> str:
        return self.jj_out("log", "--no-graph", "-r", rev, "-T", "change_id.shortest(12)")

    def commit_id(self, rev: str = "@") -> str:
        # The git commit id changes when a commit is rewritten (unlike the stable
        # change id). Use it to assert a frozen commit was not rewritten.
        return self.jj_out("log", "--no-graph", "-r", rev, "-T", "commit_id")

    def ids(self, revset: str) -> set[str]:
        out = self.jj_out(
            "log", "--no-graph", "-r", revset, "-T", 'change_id.shortest(12) ++ "\n"'
        )
        return {line for line in out.splitlines() if line}

    def log_graph(self, revset: str = "::@ | remote_bookmarks()") -> str:
        template = (
            'change_id.shortest(8)'
            ' ++ if(current_working_copy, " @", "")'
            ' ++ if(empty, " (empty)", "")'
            ' ++ " [" ++ separate(",", bookmarks) ++ "]"'
            ' ++ " (" ++ separate(",", parents.map(|p| p.change_id().shortest(8))) ++ ")"'
            ' ++ " " ++ description.first_line() ++ "\n"'
        )
        return self.jj_out("log", "--no-pager", "-r", revset, "-T", template)

    # --- remotes and sync ----------------------------------------------------
    def register_remote(self, name: str, definition=None) -> Path:
        """Add a git remote. ``definition`` is a bare-repo path or a ``Repo``.

        With ``definition=None`` the harness makes a fresh bare repo for it.
        Returns the bare-repo path.
        """
        if definition is None:
            bare = self.harness.make_bare(name)
        elif isinstance(definition, Repo):
            bare = definition.path
        else:
            bare = Path(definition)
        self.jj("git", "remote", "add", name, str(bare))
        return bare

    def apply_config(self) -> "Repo":
        """Install the base file and every persistent (file-layer) entry.

        The base file goes to the canonical path from ``jj config path
        --<base_scope>`` (jj does not read ``.jj/repo/config.toml`` directly).
        """
        self.install_base_file()
        for scope, key, value in self.cfg.persistent():
            self.jj("config", "set", f"--{scope}", key, _toml_value(value))
        return self

    def install_base_file(self) -> "Repo":
        if self.cfg.base_toml is None:
            return self
        dest = Path(self.jj_out("config", "path", f"--{self.cfg.base_scope}"))
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(self.cfg.base_toml, dest)
        return self

    def define_config(self, scope: str, dotted: str, value) -> "Repo":
        """Set one config entry now at the given scope (also recorded in cfg)."""
        self.cfg.set(dotted, value, scope=scope)
        if scope != "flag":
            self.jj("config", "set", f"--{scope}", dotted, _toml_value(value))
        return self

    def define_alias(self, name: str, argv, *, scope: str = "repo") -> "Repo":
        """Record and write a command alias now (use after ``mkrepo``)."""
        self.cfg.alias(name, argv, scope=scope)
        self.jj("config", "set", f"--{scope}", f"aliases.{_toml_key(name)}", _toml_value(list(argv)))
        return self

    def bookmark_set(self, name: str, rev: str) -> "Repo":
        self.jj("bookmark", "set", name, "-r", rev, "--allow-backwards")
        return self

    def push(self, remote: str, bookmark: str) -> "Repo":
        self.jj("git", "push", "--remote", remote, "--bookmark", bookmark)
        return self

    def push_to(self, remote: str, local_bookmark: str, remote_bookmark: str) -> "Repo":
        """Push a local bookmark to a differently-named remote bookmark via git."""
        self.git("push", remote, f"{local_bookmark}:{remote_bookmark}")
        self.jj("git", "import")
        return self

    def fetch(self, *remotes: str) -> "Repo":
        args = ["git", "fetch"]
        for remote in remotes:
            args += ["--remote", remote]
        self.jj(*args)
        return self


@dataclasses.dataclass
class Harness:
    """Owns the isolated env and every repo/bare-remote a test creates.

    Repos and bare remotes live under one temp root. ``cleanup`` removes them.
    """

    root: Path
    _repos: list[Repo] = dataclasses.field(default_factory=list)
    _n_repos: int = 0
    _n_bares: int = 0

    def __post_init__(self):
        home = self.root / "home"
        for sub in ("home", "xcfg", "xdata", "xstate", "xcache", "repos", "remotes"):
            (self.root / sub).mkdir(parents=True, exist_ok=True)
        jj_config = self.root / "jj.toml"
        jj_config.write_text(
            '[user]\n'
            'name = "Harness User"\n'
            'email = "harness@example.invalid"\n'
            '[ui]\n'
            'paginate = "never"\n'
        )
        self.env = {
            **os.environ,
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(self.root / "xcfg"),
            "XDG_DATA_HOME": str(self.root / "xdata"),
            "XDG_STATE_HOME": str(self.root / "xstate"),
            "XDG_CACHE_HOME": str(self.root / "xcache"),
            "JJ_CONFIG": str(jj_config),
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
            # No interactive editor may ever open in a test.
            "JJ_EDITOR": "true",
            "EDITOR": "true",
            "VISUAL": "true",
            "GIT_EDITOR": "true",
        }
        # Neutralize git's other config-injection and identity vars. A developer's
        # interactive shell may export these; they must not leak into the isolated
        # env (git applies GIT_CONFIG_* regardless of GIT_CONFIG_GLOBAL=/dev/null).
        for key in list(self.env):
            if key.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_")):
                del self.env[key]
        for key in (
            "GIT_CONFIG",
            "GIT_CONFIG_COUNT",
            "GIT_AUTHOR_NAME",
            "GIT_AUTHOR_EMAIL",
            "GIT_AUTHOR_DATE",
            "GIT_COMMITTER_NAME",
            "GIT_COMMITTER_EMAIL",
            "GIT_COMMITTER_DATE",
        ):
            self.env.pop(key, None)

    def mkrepo(self, name: str | None = None, *, cfg: JJConfig | None = None) -> Repo:
        self._n_repos += 1
        name = name or f"repo{self._n_repos}"
        path = (self.root / "repos" / name).resolve()
        path.mkdir(parents=True, exist_ok=True)
        repo = Repo(
            path=path,
            env=self.env,
            cfg=cfg or JJConfig.without_slot(),
            harness=self,
        )
        repo.jj("git", "init", "--colocate")
        repo.apply_config()
        self._repos.append(repo)
        return repo

    def make_bare(self, label: str = "remote") -> Path:
        self._n_bares += 1
        path = (self.root / "remotes" / f"{label}{self._n_bares}.git").resolve()
        path.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["git", "init", "--bare", "-q", str(path)],
            env=self.env,
            check=True,
            capture_output=True,
            text=True,
        )
        return path

    def slot_config(self) -> JJConfig:
        """Return a ``JJConfig`` from the rendered fork slot, or skip.

        The check derivation and the ``devenv shell`` export
        ``JJ_FORK_CONFIG_TOML``. Without it, tests that need the real fork
        aliases are skipped.
        """
        toml = os.environ.get("JJ_FORK_CONFIG_TOML")
        if not toml:
            pytest.skip("JJ_FORK_CONFIG_TOML is not set (run in the devenv or the check)")
        return JJConfig.from_slot(toml)

    def cleanup(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


@pytest.fixture
def harness(tmp_path) -> Harness:
    h = Harness(root=(tmp_path / "jjx").resolve())
    try:
        yield h
    finally:
        h.cleanup()


@pytest.fixture
def mkrepo(harness):
    """Return the repo factory. Every repo it makes is cleaned up on teardown."""
    return harness.mkrepo
