---
type: Reference
description: Prefer committed pytest tests with a nix-shell shebang that builds the tool onto PATH over one-off manual test commands.
timestamp: 2026-07-30T16:23:55+02:00
---

# Testing conventions

> **TL;DR:** when you find yourself running a one-off command to test out a functionality, write
> a committed `pytest` test instead (or in addition) — one whose `nix-shell` shebang builds the
> tool fresh onto PATH and exercises the **actual built artifact** as a black box. The throwaway
> command becomes a permanent, reproducible test the next person (or agent) can just run.

## Why

Ad-hoc "let me just run it and eyeball the output" commands verify a functionality once, then
evaporate. A committed test:

- **survives** — the next change re-runs it automatically instead of silently regressing;
- **exercises the real package** — black-box `subprocess` calls to the built binary catch
  packaging bugs (wrapper args, `runtimeDeps`, arg parsing, `argc`/`--help` dispatch) that a
  pure-source unit test would miss;
- **is self-bootstrapping** — the `nix-shell` shebang builds the package-under-test from its own
  `default.nix` and puts it on PATH, so `./tool_test.py` (or `pytest tool_test.py`) works with no
  devenv shell active. See [nix-shell-shebang.md](nix-shell-shebang.md) for the shebang mechanics.

## The pattern

```python
#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages(ps: [ps.pytest])" -p "(callPackage ./default.nix { })" -p jujutsu -p git
"""Self-test: exercises the built binary from PATH, not the source."""
import subprocess


def run(*args, cwd=None, check=True):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=check)


def test_names_session_uses_overrides_and_llm_prefix():
    out = run("kdn-slug", "names", "--type", "session", "--repo", "myrepo", "--session-id", "deadbeef")
    assert out.stdout.strip() == "llm:myrepo:deadbeef"
```

Key points:

- `-p "(callPackage ./default.nix { })"` builds the package under test and adds its `bin/` to
  PATH — the test invokes the tool **by name** (`"kdn-slug"`), never by source path.
- Use disposable fixtures for environment-dependent behavior — e.g. a `tmp_path`-scoped
  jj-colocated repo stub with a fake remote to test repo auto-discovery, matching this repo's
  own jj-colocated-with-git topology. Resolve `tmp_path` through `/private` on macOS so it
  matches what `jj root` / `git rev-parse` report.
- Run either way — both build first: `./tool_test.py` directly (shebang drives nix-shell), or
  `pytest tool_test.py` from inside a `nix-shell -p "(callPackage ./default.nix {})" …`.
- End the file with `if __name__ == "__main__": raise SystemExit(pytest.main([__file__, "-v"]))`
  so direct execution runs pytest.

## Wire it into flake `checks`

Attach the suite as a `passthru.tests.pytest` on the package (the nixpkgs convention — attached,
not built by default), and reference it from `checks/default.nix` so `nix flake check` runs it.
Live examples: `packages/llm/kdn-slug/kdn_slug_test.py` and
`packages/llm/zellij-llm/zellij_llm_test.py`.

## Regression discipline

When a bug is found by a manual test-drive (e.g. a session name joined with a `/` that zellij
rejects, or duplicated streamed output), add an assertion that would have caught it **before**
fixing — the fix isn't done until the previously-passing-but-wrong assertion is corrected and a
new one pins the intended behavior.
