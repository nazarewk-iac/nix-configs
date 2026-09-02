"""Phase 0 smoke tests — prove the harness itself works.

These tests use only ``JJConfig.without_slot()``. They do not need the fork
slot or ``JJ_FORK_CONFIG_TOML``. They validate the parts every later test group
depends on: complete ``$HOME`` isolation, history building, deterministic commit
times, the ``JJConfig`` overlay shortcuts, and headless bare push and fetch.

Each test is a small, readable worked example of the ``mkrepo`` / ``Repo`` /
``JJConfig`` API. Read them as usage samples.
"""

from conftest import JJConfig


# --- isolation ---------------------------------------------------------------
def test_user_comes_from_the_isolated_config_not_the_real_home(harness, mkrepo):
    """jj reads the harness ``JJ_CONFIG``, never the developer's real config.

    The env points HOME, the XDG dirs, JJ_CONFIG, and the git global/system
    config into a temp tree. So the commit author is always the harness user.
    """
    repo = mkrepo()
    assert repo.jj_out("config", "get", "user.name") == "Harness User"
    assert repo.jj_out("config", "get", "user.email") == "harness@example.invalid"
    # every path stays under the per-test temp root:
    assert str(repo.path).startswith(str(harness.root))


# --- history building --------------------------------------------------------
def test_commit_builds_a_linear_history_and_leaves_an_empty_working_copy(mkrepo):
    """``Repo.commit`` describes ``@`` and starts a fresh empty ``@``.

    After two commits the graph is ``root -> c1 -> c2 -> @`` (empty).
    """
    repo = mkrepo()
    c1 = repo.commit("feat: one", {"a.txt": "1\n"})
    c2 = repo.commit("feat: two", {"b.txt": "2\n"})

    assert repo.ids("@-") == {c2}
    assert repo.ids("@--") == {c1}
    assert repo.ids('description(substring:"feat: one")') == {c1}

    graph = repo.log_graph()
    assert "feat: one" in graph
    assert "feat: two" in graph


# --- deterministic timestamps ------------------------------------------------
def test_commit_times_increase_so_latest_is_stable(mkrepo):
    """Each commit gets an explicit, increasing time.

    ``latest()`` and the ``*-tip`` aliases pick by commit time, so a stable
    order needs no sleeps.
    """
    repo = mkrepo()
    c1 = repo.commit("feat: first", {"a.txt": "1\n"})
    c2 = repo.commit("feat: second", {"b.txt": "2\n"})

    t1 = repo.jj_out("log", "--no-graph", "-r", c1, "-T", "committer.timestamp()")
    t2 = repo.jj_out("log", "--no-graph", "-r", c2, "-T", "committer.timestamp()")
    # same ISO format, so lexical order equals time order:
    assert t1 < t2
    # the newest described commit wins latest():
    assert repo.ids("latest(description(substring:'feat:'))") == {c2}


# --- JJConfig overlay shortcuts ----------------------------------------------
def test_revset_alias_and_user_alias_overlays_apply(mkrepo):
    """Overlays apply as ``--config`` args on every jj call.

    A revset alias resolves, and a user command alias runs.
    """
    cfg = JJConfig.without_slot()
    repo = mkrepo(cfg=cfg)
    tip = repo.commit("feat: x", {"a.txt": "1\n"})

    cfg.revset_alias("mine_tip", "heads(::@- & ~empty())")
    assert repo.ids("mine_tip") == {tip}

    # Command aliases cannot load from --config, so they go into the repo config
    # file via define_alias (jj refuses `aliases.*` passed as --config).
    repo.define_alias("lg", ["log", "--no-graph", "-r", "@-", "-T", "change_id.shortest(12)"])
    assert repo.jj_out("lg") == tip


def test_set_records_a_dotted_config_entry(mkrepo):
    """``JJConfig.set`` adds a dotted-key ``--config`` entry."""
    cfg = JJConfig.without_slot()
    mkrepo(cfg=cfg)
    cfg.set("ui.paginate", "never")
    assert "ui.paginate=\"never\"" in cfg.config_args()


def test_deferred_overlay_is_inactive_until_activated(mkrepo):
    """A deferred overlay does not apply until ``activate_deferred``.

    This is how the topology fixtures avoid the trap where an alias that names a
    not-yet-created ref (``trunk()`` / ``immutable_heads()``) breaks every jj
    command before the ref exists.
    """
    cfg = JJConfig.without_slot()
    repo = mkrepo(cfg=cfg)
    repo.commit("feat: y", {"a.txt": "1\n"})

    cfg.revset_alias("later_tip", "heads(::@)", deferred=True)
    # before activation the alias is undefined, so the query fails:
    before = repo.jj("log", "--no-graph", "-r", "later_tip", check=False)
    assert before.returncode != 0

    cfg.activate_deferred()
    # after activation the alias resolves:
    assert repo.jj_out("log", "--no-graph", "-r", "later_tip", "-T", "change_id.shortest(12)")


# --- config scopes -----------------------------------------------------------
def test_config_scopes_target_each_layer_and_flag_wins(mkrepo):
    """A config entry can target flag, user, repo, or workspace.

    File layers (user/repo/workspace) are written with ``jj config set`` by
    ``define_config``; the flag layer applies per call. The flag layer wins over
    a file layer (highest precedence).
    """
    cfg = JJConfig.without_slot()
    repo = mkrepo(cfg=cfg)
    repo.commit("feat: base", {"a.txt": "1\n"})

    # each file-layer alias resolves once written to that scope:
    for scope in ("user", "repo", "workspace"):
        repo.define_config(scope, f"revset-aliases.tip_{scope}", "heads(::@)")
        assert repo.jj_out(
            "log", "--no-graph", "-r", f"tip_{scope}", "-T", "change_id.shortest(12)"
        )

    # precedence: a flag alias overrides the same alias set at repo scope.
    repo.define_config("repo", "revset-aliases.who", "root()")
    cfg.revset_alias("who", "@")  # flag scope (the default)
    assert repo.ids("who") == repo.ids("@")
    assert repo.ids("who") != repo.ids("root()")


# --- remotes -----------------------------------------------------------------
def test_bare_remote_push_and_fetch_between_two_repos(mkrepo):
    """``register_remote`` makes a bare repo; push and fetch work headless.

    A second repo reads the pushed bookmark through ``remote_bookmarks``.
    """
    repo = mkrepo()
    bare = repo.register_remote("origin")
    base = repo.commit("feat: base", {"a.txt": "1\n"})
    repo.bookmark_set("main", base)
    repo.push("origin", "main")

    other = mkrepo()
    other.register_remote("origin", bare)
    other.fetch("origin")

    assert other.ids('remote_bookmarks(remote="origin")')
    assert "feat: base" in other.log_graph('remote_bookmarks(remote="origin")')
