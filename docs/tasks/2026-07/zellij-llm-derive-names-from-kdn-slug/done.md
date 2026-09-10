---
type: Task
description: Solution — zellij-llm derives its session name from kdn-slug by default, capped to the zellij socket-path limit, with a verbatim --session override.
status: done
authored_by: agent
timestamp: 2026-07-31T14:45:00+02:00
---

# Solution — derive names from kdn-slug

## Root cause analysis

Every `zellij-llm` subcommand needed a `--session` value. The caller had to run
`kdn-slug names --type session` first and pass the result. This was boilerplate. It also hid a
hard failure: the default derived name overflowed zellij's 103-byte IPC socket path and failed
late in `spawn` with a cryptic error. An earlier workaround set a private
`ZELLIJ_SOCKET_DIR=/tmp/zellij` default in `zellij-llm.sh`. That masked the length problem and
hid the tool's sessions from the user's plain `zellij list-sessions`.

## Solution

- `zellij-llm` derives the default `--session` from `kdn-slug` internally
  (`packages/llm/zellij-llm/zellij-llm.sh`, `_session_name`). The common case is now
  `zellij-llm spawn --pane <slug>` with no `--session`.
- `--session <name>` overrides the derived name and is used verbatim. When set, the tool does
  not call `kdn-slug`.
- The tool caps the derived name to fit the socket path. `_socket_budget` computes the free
  bytes as `103 - len(<socket-dir>/contract_version_1/)` and passes that as `--max-len` to
  `kdn-slug`. An explicit `--max-len` tightens the cap further but never exceeds the budget.
- `zellij-llm` forwards the correctness knobs to `kdn-slug`: `--sep`, `--repo-sep`, `--max-len`,
  and repeatable `--tag`.
- The private `ZELLIJ_SOCKET_DIR` default is removed from `zellij-llm.sh`. The tool now uses
  zellij's own default socket location, so its sessions stay visible under the user's plain
  `zellij list-sessions`. `ZELLIJ_SOCKET_DIR` stays a test-only device, set only by the pytest
  fixture.
- `_validate_socket_len` fails early with a clear, actionable message when the derived or passed
  session name overflows the socket path.
- `kdn-slug` is added to `zellij-llm`'s `runtimeInputs`
  (`packages/llm/zellij-llm/default.nix`). `argc` is added to the devenv shell (`devenv.nix`) so
  the standalone scripts run.

## Verification steps

- `nix build .#packages.aarch64-darwin.zellij-llm` — shellcheck-clean build.
- `nix build .#packages.aarch64-darwin.zellij-llm.tests.pytest` — 15 tests pass, including
  `test_derived_session_fits_socket_and_runs` (derive path, `--max-len 24`) and
  `test_spawn_rejects_oversized_session_name` (early length error).
- Manual: with the real default socket dir (budget 24 on this host's long `$TMPDIR`),
  `kdn-slug names --type session --max-len 24` returns `llm:nix-configs:deadbeef` (24 chars,
  fits). With no `--session`, `spawn` prints the short derived session name it chose.

## Follow-up notes

- Committed as `feat(zellij-llm): derive session name from kdn-slug; add watch/wait +
  persist-by-default` (change `kkxrzzxx`). This commit also covers the sibling docs-clarity task
  ([[zellij-llm-docs-clarity]]).
