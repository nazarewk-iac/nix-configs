---
type: Task
description: `atuin` 18.23.0 fails its darwin e2e tests, so every darwin switch fails; skip the checks on darwin until the package passes them again.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-14T00:03:02+02:00
---

# Skip the `atuin` checks on darwin

> ✅ **Done** — see the solution in [done.md](done.md).

## Context

The 2026-10-11 flake update moved `nixpkgs` to `7fd4004d`. It bumped `atuin` to 18.23.0. On the
`aarch64-darwin` host `anji`, `darwin-rebuild switch` then failed, because `atuin` fails its own
test suite.

## Problem

`atuin` 18.23.0 fails two darwin e2e test binaries:

- `e2e_capture::filtered_commands_leave_no_captured_output` — "timed out waiting for the last
  command's captured output".
- `e2e_pty` — 13 tests fail, for example `selection_returns_for_editing` and
  `shell_hooks_record_history`.

Both binaries drive an interactive bash in a pty. The failure is not flaky: a second run failed the
same way. It is nixpkgs issue
[#573527](https://github.com/NixOS/nixpkgs/issues/573527) (`Build failure: atuin`), which is open
and reproducible on Hydra. It blocks every darwin switch in this repository, and no fix has landed.

## Approach

Add a darwin-only overlay that sets `doCheck = false` for `atuin`, with a comment that names the
issue and states when to remove the entry.
